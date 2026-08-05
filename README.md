# Kubernetes

1. Image build & push:
```bash
docker build -t YOUR_REGISTRY/optiyo-api:13.1 ./backend
docker push YOUR_REGISTRY/optiyo-api:13.1
```

2. Secret oluştur (şifreleri değiştir):
```bash
kubectl create namespace optiyo
kubectl -n optiyo create secret generic optiyo-env \
  --from-literal=DATABASE_URL='postgresql://optiyo:PASS@postgres:5432/optiyo_db' \
  --from-literal=REDIS_URL='redis://redis:6379/0' \
  --from-literal=SECRET_KEY='uzun-gizli-anahtar'
```

3. Manifestleri düzenle (image adını değiştir) ve uygula:
```bash
kubectl apply -f k8s/
```
