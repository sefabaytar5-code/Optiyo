
import 'package:flutter/material.dart';
import '../models/deal_model.dart';

class HomeScreen extends StatelessWidget {
  HomeScreen({super.key});

  final List<Deal> dummyDeals = [
    Deal(
      id: '1',
      title: 'Trendyol Süper Fırsat',
      description: 'Seçili elektronik ürünlerde sepette ekstra %20 indirim.',
      discountCode: 'SUPER20',
      category: 'Elektronik',
    ),
    Deal(
      id: '2',
      title: 'Hepsiburada Gizli Kampanya',
      description: 'Bu linke özel market alışverişlerinde 100 TL indirim kuponu.',
      discountCode: 'MARKET100',
      category: 'Market',
      isHidden: true,
    ),
    Deal(
      id: '3',
      title: 'Amazon Günün Fırsatı',
      description: 'Giyim kategorisinde 3 al 2 öde kampanyası aktif!',
      discountCode: null,
      category: 'Moda',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔥 İndirim ve Fırsatlar'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12.0),
        itemCount: dummyDeals.length,
        itemBuilder: (context, index) {
          final deal = dummyDeals[index];
          return Card(
            elevation: 3,
            margin: const EdgeInsets.only(bottom: 12.0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        deal.category,
                        style: const TextStyle(
                          color: Colors.deepOrange,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      if (deal.isHidden)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '🔒 Gizli Kampanya',
                            style: TextStyle(
                                color: Colors.purple, fontSize: 10),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    deal.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    deal.description,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                  ),
                  if (deal.discountCode != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Kupon Kodu: ${deal.discountCode}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                            ),
                          ),
                          const Text(
                            'Kopyala',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
