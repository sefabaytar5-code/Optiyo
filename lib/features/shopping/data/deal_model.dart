class DealModel {
  final String id;
  final String title;
  final String description;
  final String? discountCode;
  final String category;
  final double currentPrice;
  final double oldPrice;
  final bool isHidden;

  DealModel({
    required this.id,
    required this.title,
    required this.description,
    this.discountCode,
    required this.category,
    required this.currentPrice,
    required this.oldPrice,
    this.isHidden = false,
  });
}
