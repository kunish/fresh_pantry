import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/food_details.dart';
import '../models/ingredient.dart';
import '../services/food_details_client.dart';
import '../services/open_food_facts_service.dart';
import '../storage/food_details_repo.dart';
import 'storage_service_provider.dart';

export '../services/food_details_client.dart'
    show FoodDetailsClient, OpenFoodFactsDetailsClient;
export '../services/open_food_facts_service.dart' show FoodSearchResult;
export '../storage/food_details_repo.dart'
    show
        FoodDetailsRepository,
        fallbackFoodDetailsFor,
        foodDetailsCacheKeyFor,
        foodDetailsCacheStorageKey;

/// Injectable name -> image-preview search over Open Food Facts.
///
/// The Add-Ingredient screen reads this instead of calling the static
/// [OpenFoodFactsService.searchByName] directly, so the lookup has a DI
/// boundary (overridable in widget tests) and the View no longer performs HTTP
/// itself. This is the search/image counterpart to [foodDetailsClientProvider]
/// (which covers the heavier details path).
typedef FoodImageSearch = Future<FoodSearchResult?> Function(String name);

final foodImageSearchProvider = Provider<FoodImageSearch>(
  (ref) => OpenFoodFactsService.searchByName,
);

final foodDetailsClientProvider = Provider<FoodDetailsClient>(
  (ref) => const OpenFoodFactsDetailsClient(),
);

final foodDetailsRepositoryProvider = Provider<FoodDetailsRepository>((ref) {
  return FoodDetailsRepository(
    storage: ref.read(storageAdapterProvider),
    client: ref.watch(foodDetailsClientProvider),
  );
});

final foodDetailsProvider = FutureProvider.autoDispose
    .family<FoodDetails, Ingredient>((ref, ingredient) {
      return ref.watch(foodDetailsRepositoryProvider).detailsFor(ingredient);
    });
