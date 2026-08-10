import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_download_service.dart';

import 'model_download_http_fixture.dart';

part 'model_download_service_fixture.dart';
part 'model_download_service_fresh_cases.dart';
part 'model_download_service_restart_error_cases.dart';
part 'model_download_service_resume_validator_cases.dart';

void main() {
  _registerModelDownloadServiceFreshCases();
  _registerModelDownloadServiceResumeValidatorCases();
  _registerModelDownloadServiceRestartErrorCases();
}
