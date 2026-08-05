"""
Optiyo V13.1 — FastAPI backend
Public ürün API + JWT auth + scraper + affiliate
"""
import os
import random
import json
import uuid
import time
from datetime import datetime, timedelta, timezone
from typing import List, Optional, Dict, Any
from urllib.parse import urlencode, urlparse, parse_qs, urlunparse

from dotenv import load_dotenv
load_dotenv()

from sqlalchemy import (
    create_engine, Column, String, DateTime, ForeignKey,
    Numeric, Text, Boolean, Float, Integer, func,
)
from sqlalchemy.orm import sessionmaker, Session, relationship, declarative_base
from sqlalchemy.dialects.postgresql import UUID

from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Query, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from pydantic import BaseModel, EmailStr, Field, ConfigDict

from passlib.context import CryptContext
from jose import jwt, JWTError
from bs4 import BeautifulSoup
from playwright.sync_api import sync_playwright
import google.generativeai as genai
from celery import Celery
from celery.exceptions import MaxRetriesExceededError

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://optiyo:optiyo_secret@localhost:5432/optiyo_db")
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
SECRET_KEY = os.getenv("SECRET_KEY", "dev-only-change-me-32-characters-min")
ALGORITHM = "HS256"
ACCESS_MIN = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "30"))
REFRESH_DAYS = int(os.getenv("REFRESH_TOKEN_EXPIRE_DAYS", "7"))
TRENDYOL_AFFILIATE_ID = os.getenv("TRENDYOL_AFFILIATE_ID", "")
HEPSIBURADA_AFFILIATE_ID = os.getenv("HEPSIBURADA_AFFILIATE_ID", "")
AMAZON_AFFILIATE_TAG = os.getenv("AMAZON_AFFILIATE_TAG", "")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()
pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto")
security = HTTPBearer(auto_error=False)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


class User(Base):
    __tablename__ = "users"
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email = Column(String(150), unique=True, index=True, nullable=False)
    name = Column(String(100), nullable=False)
    password_hash = Column(String(255), nullable=False)
    role = Column(String(20), default="USER")
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class Product(Base):
    __tablename__ = "products"
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    barcode = Column(String(50), unique=True, index=True, nullable=False)
    name = Column(String(255), nullable=False, index=True)
    brand = Column(String(100), nullable=False)
    category = Column(String(100), nullable=False)
    image_url = Column(Text, nullable=True)
    is_active = Column(Boolean, default=True)
    ai_score = Column(Float, default=50.0)
    stock = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    prices = relationship("Price", back_populates="product", cascade="all, delete-orphan")


class Price(Base):
    __tablename__ = "prices"
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id", ondelete="CASCADE"))
    store = Column(String(100), nullable=False)
    price = Column(Numeric(12, 2), nullable=False)
    store_url = Column(Text, nullable=True)
    stock = Column(Integer, nullable=True)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    product = relationship("Product", back_populates="prices")


class PriceHistory(Base):
    __tablename__ = "price_histories"
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id", ondelete="CASCADE"))
    store = Column(String(100), nullable=False)
    price = Column(Numeric(12, 2), nullable=False)
    recorded_at = Column(DateTime(timezone=True), server_default=func.now())


class AffiliateClick(Base):
    __tablename__ = "affiliate_clicks"
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id", ondelete="CASCADE"))
    store = Column(String(100), nullable=False)
    original_url = Column(Text, nullable=True)
    affiliate_url = Column(Text, nullable=True)
    commission = Column(Numeric(10, 2), default=0)
    status = Column(String(30), default="PENDING")
    click_date = Column(DateTime(timezone=True), server_default=func.now())


def hash_pw(p: str) -> str:
    return pwd_ctx.hash(p)


def verify_pw(p: str, h: str) -> bool:
    return pwd_ctx.verify(p, h)


def make_token(data: dict, minutes: int = None, days: int = None, typ: str = "access") -> str:
    payload = data.copy()
    if days:
        exp = datetime.now(timezone.utc) + timedelta(days=days)
    else:
        exp = datetime.now(timezone.utc) + timedelta(minutes=minutes or ACCESS_MIN)
    payload.update({"exp": exp, "type": typ})
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def get_optional_user(
    cred: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: Session = Depends(get_db),
) -> Optional[User]:
    if not cred:
        return None
    try:
        payload = jwt.decode(cred.credentials, SECRET_KEY, algorithms=[ALGORITHM])
        if payload.get("type") != "access":
            return None
        user = db.query(User).filter(User.id == uuid.UUID(payload["sub"])).first()
        if user and user.is_active:
            return user
    except JWTError:
        pass
    return None


def get_current_user(user: Optional[User] = Depends(get_optional_user)) -> User:
    if not user:
        raise HTTPException(401, "Token gerekli")
    return user


def require_admin(user: User = Depends(get_current_user)) -> User:
    if user.role != "ADMIN":
        raise HTTPException(403, "Admin gerekli")
    return user


STORE_CONFIG = {
    "trendyol": {"param": "merchantId", "id": TRENDYOL_AFFILIATE_ID},
    "hepsiburada": {"param": "affiliate", "id": HEPSIBURADA_AFFILIATE_ID},
    "amazon": {"param": "tag", "id": AMAZON_AFFILIATE_TAG},
}


def build_affiliate_url(store: str, original_url: str, click_id: str) -> str:
    parsed = urlparse(original_url)
    q = parse_qs(parsed.query)
    key = store.lower()
    for k, cfg in STORE_CONFIG.items():
        if k in key and cfg["id"]:
            q[cfg["param"]] = [cfg["id"]]
            break
    q["optiyo_cid"] = [click_id]
    return urlunparse((parsed.scheme, parsed.netloc, parsed.path, parsed.params, urlencode(q, doseq=True), parsed.fragment))


USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15",
]


def _clean_price(t: str) -> float:
    if not t:
        return 0.0
    try:
        return float(t.replace("TL", "").replace("₺", "").replace(".", "").replace(",", ".").strip())
    except Exception:
        return 0.0


class StoreScraper:
    @classmethod
    def scrape(cls, store: str, url: str) -> Dict[str, Any]:
        try:
            with sync_playwright() as p:
                browser = p.chromium.launch(headless=True, args=["--disable-blink-features=AutomationControlled"])
                page = browser.new_page(user_agent=random.choice(USER_AGENTS), locale="tr-TR")
                page.goto(url, timeout=35000, wait_until="domcontentloaded")
                page.wait_for_timeout(1500)
                html = page.content()
                browser.close()
            if any(x in html.lower() for x in ("captcha", "robot", "challenge")):
                return {"status": "captcha", "price": 0.0}
            soup = BeautifulSoup(html, "html.parser")
            s = store.lower()
            price = 0.0
            if "trendyol" in s:
                tag = soup.find("span", class_="prc-dsc") or soup.find(attrs={"data-testid": "price-current-price"})
                price = _clean_price(tag.get_text()) if tag else 0.0
            elif "hepsiburada" in s:
                tag = soup.find("span", id="offering-price") or soup.find(attrs={"data-test-id": "price-current-price"})
                price = _clean_price(tag.get_text()) if tag else 0.0
            elif "amazon" in s:
                w = soup.find("span", class_="a-price-whole")
                f = soup.find("span", class_="a-price-fraction")
                if w:
                    price = float(f"{w.get_text().replace('.', '').replace(',', '').strip()}.{f.get_text().strip() if f else '00'}")
            elif "migros" in s:
                tag = soup.find("span", class_="amount")
                price = _clean_price(tag.get_text()) if tag else 0.0
            return {"status": "success", "price": price}
        except Exception as e:
            return {"status": "error", "message": str(e), "price": 0.0}


genai.configure(api_key=GEMINI_API_KEY)
celery_app = Celery("optiyo", broker=REDIS_URL, backend=REDIS_URL)
celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="Europe/Istanbul",
    enable_utc=True,
    beat_schedule={"scrape-hourly": {"task": "main.enqueue_scrapes", "schedule": 3600.0}},
)


@celery_app.task(bind=True, name="main.scrape_one", max_retries=3, default_retry_delay=60)
def scrape_one(self, product_id: str, store: str, url: str):
    db = SessionLocal()
    try:
        product = db.query(Product).filter(Product.id == uuid.UUID(product_id)).first()
        if not product:
            return {"error": "not found"}
        time.sleep(random.uniform(1, 2.5))
        r = StoreScraper.scrape(store, url)
        if r["status"] != "success" or r["price"] <= 0:
            raise Exception(r.get("message", r["status"]))
        row = db.query(Price).filter(Price.product_id == product.id, Price.store == store).first()
        if row:
            row.price = r["price"]
            row.store_url = url
            row.updated_at = datetime.now(timezone.utc)
        else:
            db.add(Price(product_id=product.id, store=store, price=r["price"], store_url=url))
        db.add(PriceHistory(product_id=product.id, store=store, price=r["price"]))
        db.commit()
        return {"ok": True, "price": r["price"]}
    except Exception as e:
        db.rollback()
        try:
            raise self.retry(exc=e)
        except MaxRetriesExceededError:
            return {"failed": str(e)}
    finally:
        db.close()


@celery_app.task(name="main.enqueue_scrapes")
def enqueue_scrapes():
    db = SessionLocal()
    try:
        n = 0
        for p in db.query(Product).filter(Product.is_active == True).all():
            for pr in db.query(Price).filter(Price.product_id == p.id).all():
                if pr.store_url:
                    scrape_one.delay(str(p.id), pr.store, pr.store_url)
                    n += 1
        return {"enqueued": n}
    finally:
        db.close()


def is_ean13(b: str) -> bool:
    if not b or not b.isdigit() or len(b) != 13:
        return False
    d = [int(x) for x in b]
    c = sum(d[i] if i % 2 == 0 else d[i] * 3 for i in range(12)) % 10
    return ((10 - c) % 10) == d[12]


app = FastAPI(title="Optiyo API", version="13.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class RegisterIn(BaseModel):
    email: EmailStr
    name: str
    password: str = Field(min_length=8)


class LoginIn(BaseModel):
    email: EmailStr
    password: str


class TokenOut(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class ProductOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    barcode: str
    name: str
    brand: str
    category: str
    image_url: Optional[str] = None
    ai_score: Optional[float] = None
    stock: Optional[int] = None


class PriceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    store: str
    price: float
    store_url: Optional[str] = None
    stock: Optional[int] = None
    updated_at: datetime


class ClickIn(BaseModel):
    product_id: uuid.UUID
    store: str
    original_url: Optional[str] = None


@app.get("/health")
def health():
    return {"status": "ok", "version": "13.1.0"}


@app.post("/api/v1/auth/register", status_code=201)
def register(body: RegisterIn, db: Session = Depends(get_db)):
    if db.query(User).filter(User.email == body.email).first():
        raise HTTPException(400, "E-posta kayıtlı")
    u = User(email=body.email, name=body.name, password_hash=hash_pw(body.password))
    db.add(u)
    db.commit()
    db.refresh(u)
    return {"user_id": str(u.id)}


@app.post("/api/v1/auth/login", response_model=TokenOut)
def login(body: LoginIn, db: Session = Depends(get_db)):
    u = db.query(User).filter(User.email == body.email).first()
    if not u or not verify_pw(body.password, u.password_hash):
        raise HTTPException(401, "Hatalı bilgi")
    if not u.is_active:
        raise HTTPException(403, "Hesap kapalı")
    return {
        "access_token": make_token({"sub": str(u.id), "role": u.role}, minutes=ACCESS_MIN, typ="access"),
        "refresh_token": make_token({"sub": str(u.id)}, days=REFRESH_DAYS, typ="refresh"),
    }


@app.post("/api/v1/auth/refresh", response_model=TokenOut)
def refresh(cred: HTTPAuthorizationCredentials = Depends(security), db: Session = Depends(get_db)):
    if not cred:
        raise HTTPException(401, "Token gerekli")
    try:
        payload = jwt.decode(cred.credentials, SECRET_KEY, algorithms=[ALGORITHM])
        if payload.get("type") != "refresh":
            raise HTTPException(401, "Geçersiz refresh")
        u = db.query(User).filter(User.id == uuid.UUID(payload["sub"])).first()
        if not u:
            raise HTTPException(401, "Kullanıcı yok")
    except JWTError:
        raise HTTPException(401, "Geçersiz token")
    return {
        "access_token": make_token({"sub": str(u.id), "role": u.role}, minutes=ACCESS_MIN, typ="access"),
        "refresh_token": make_token({"sub": str(u.id)}, days=REFRESH_DAYS, typ="refresh"),
    }


@app.get("/api/v1/user/profile")
def profile(user: User = Depends(get_current_user)):
    return {"id": str(user.id), "email": user.email, "name": user.name, "role": user.role}


@app.get("/api/v1/products", response_model=List[ProductOut])
def products(skip: int = 0, limit: int = Query(20, le=100), db: Session = Depends(get_db)):
    return (
        db.query(Product)
        .filter(Product.is_active == True)
        .order_by(Product.ai_score.desc())
        .offset(skip)
        .limit(limit)
        .all()
    )


@app.get("/api/v1/products/search", response_model=List[ProductOut])
def search(q: str = Query(..., min_length=1), db: Session = Depends(get_db)):
    return (
        db.query(Product)
        .filter(Product.name.ilike(f"%{q}%"), Product.is_active == True)
        .order_by(Product.ai_score.desc())
        .limit(50)
        .all()
    )


@app.get("/api/v1/products/{pid}", response_model=ProductOut)
def product(pid: uuid.UUID, db: Session = Depends(get_db)):
    p = db.query(Product).filter(Product.id == pid).first()
    if not p:
        raise HTTPException(404, "Ürün yok")
    return p


@app.get("/api/v1/prices/{pid}", response_model=List[PriceOut])
def prices(pid: uuid.UUID, db: Session = Depends(get_db)):
    return db.query(Price).filter(Price.product_id == pid).all()


@app.get("/api/v1/recommendations", response_model=List[ProductOut])
def recs(limit: int = 20, db: Session = Depends(get_db)):
    return (
        db.query(Product)
        .filter(Product.is_active == True)
        .order_by(Product.ai_score.desc())
        .limit(limit)
        .all()
    )


@app.get("/api/v1/barcode/{code}")
def barcode(code: str, db: Session = Depends(get_db)):
    if not is_ean13(code):
        raise HTTPException(400, "Geçersiz EAN-13")
    p = db.query(Product).filter(Product.barcode == code).first()
    if not p:
        raise HTTPException(404, "Ürün yok")
    pr = db.query(Price).filter(Price.product_id == p.id).all()
    return {
        "product": ProductOut.model_validate(p),
        "prices": [PriceOut.model_validate(x) for x in pr],
    }


@app.post("/api/v1/scan")
async def scan(file: UploadFile = File(...)):
    data = await file.read()
    if not GEMINI_API_KEY:
        return {"status": "error", "error": "GEMINI_API_KEY tanımlı değil"}
    try:
        model = genai.GenerativeModel("gemini-1.5-flash")
        prompt = "Görseldeki ürün/etiketi oku. JSON: name, brand, price, barcode, category, raw_text"
        r = model.generate_content([{"mime_type": "image/jpeg", "data": data}, prompt])
        t = r.text.strip()
        if t.startswith("```json"):
            t = t[7:]
        if t.endswith("```"):
            t = t[:-3]
        return {"status": "success", "ocr": json.loads(t.strip())}
    except Exception as e:
        return {"status": "error", "error": str(e)}


@app.post("/api/v1/affiliate/click")
def click(body: ClickIn, user: Optional[User] = Depends(get_optional_user), db: Session = Depends(get_db)):
    if not db.query(Product).filter(Product.id == body.product_id).first():
        raise HTTPException(404, "Ürün yok")
    url = body.original_url
    if not url:
        pr = (
            db.query(Price)
            .filter(Price.product_id == body.product_id, Price.store.ilike(f"%{body.store}%"))
            .first()
        )
        if pr:
            url = pr.store_url
    c = AffiliateClick(
        user_id=user.id if user else None,
        product_id=body.product_id,
        store=body.store,
        original_url=url,
    )
    db.add(c)
    db.commit()
    db.refresh(c)
    c.affiliate_url = build_affiliate_url(body.store, url, str(c.id)) if url else f"/r/{c.id}"
    db.commit()
    return {"click_id": str(c.id), "redirect_url": c.affiliate_url}


@app.get("/r/{cid}")
def redir(cid: uuid.UUID, db: Session = Depends(get_db)):
    c = db.query(AffiliateClick).filter(AffiliateClick.id == cid).first()
    if not c or not c.affiliate_url:
        raise HTTPException(404, "Yok")
    return RedirectResponse(c.affiliate_url)


@app.post("/api/v1/scraper/enqueue-all")
def enqueue(admin: User = Depends(require_admin)):
    return {"task_id": enqueue_scrapes.delay().id}


@app.on_event("startup")
def on_startup():
    try:
        Base.metadata.create_all(bind=engine)
    except Exception as e:
        print(f"DB init warning: {e}")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
