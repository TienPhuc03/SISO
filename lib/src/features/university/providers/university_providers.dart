import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/university_repository.dart';
import '../domain/university_catalog.dart';

final universityRepositoryProvider = Provider<UniversityRepository>((ref) => UniversityRepository());

final universityCatalogProvider = FutureProvider.autoDispose<UniversityCatalog>(
  (ref) => ref.watch(universityRepositoryProvider).fetchCatalog(),
);
