import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/app.dart';
import 'package:note_secret_search/app/composition/app_composition.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      overrides: appCompositionOverrides,
      child: const NoteSecretSearchApp(),
    ),
  );
}
