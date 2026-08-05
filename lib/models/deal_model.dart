class Deal {
  final String id;
  final String title;
  final String description;
  final String? discountCode;
  final String category;
  final bool isHidden;

  Deal({
    required this.id,
    required this.title,
    required this.description,
    this.discountCode,
    required this.category,
    this.isHidden = false,
  });
}
