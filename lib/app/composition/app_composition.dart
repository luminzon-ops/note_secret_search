import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/composition/ai_composition.dart';
import 'package:note_secret_search/app/composition/content_search_composition.dart';
import 'package:note_secret_search/app/composition/core_composition.dart';
import 'package:note_secret_search/app/composition/security_composition.dart';

final List<Override> appCompositionOverrides = <Override>[
  ...coreCompositionOverrides,
  ...securityCompositionOverrides,
  ...contentSearchCompositionOverrides,
  ...aiCompositionOverrides,
];
