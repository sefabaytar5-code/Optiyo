import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/deal_model.dart';

final dealListProvider = StateNotifierProvider<DealNotifier, List<DealModel>>((ref) {
  return DealNotifier();
});

class DealNotifier extends StateNotifier<List<DealModel>> {
  DealNotifier() : super([
    DealModel(
      id: '1',
      title: 'Trendyol Elektronik Fırsatı',
      description: 'Seçili kulaklık ve akıllı saatlerde sepette ekstra %25 indirim.',
      discountCode: 'TECH25',
      category: 'Elektronik',
      currentPrice: 750.0,
      oldPrice: 1000.0,
    ),
    DealModel(
      id: '2',
      title: 'Hepsiburada Gizli Market Kuponu',
      description: 'Bu koda özel market alışverişlerinde geçerli 150 TL indirim.',
      discountCode: 'MARKET150',
      category: 'Market',
      currentPrice: 350.0,
      oldPrice: 500.0,
      isHidden: true,
    ),
    DealModel(
      id: '3',
      title: 'Amazon Moda Günleri',
      description: 'Sezon sonu giyim ürünlerinde 3 al 2 öde kampanyası.',
      discountCode: null,
      category: 'Moda',
      currentPrice: 450.0,
      oldPrice: 900.0,
    ),
  ]);

  void addDeal(DealModel deal) {
    state = [...state, deal];
  }
}
