import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterpilot_dio/flutterpilot_dio.dart';
import 'package:mocktail/mocktail.dart';

class MockRequestInterceptorHandler extends Mock
    implements RequestInterceptorHandler {}

class MockResponseInterceptorHandler extends Mock
    implements ResponseInterceptorHandler {}

class MockErrorInterceptorHandler extends Mock
    implements ErrorInterceptorHandler {}

void main() {
  late DioPilotInterceptor interceptor;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/fallback'));
    registerFallbackValue(
      Response<dynamic>(requestOptions: RequestOptions(path: '/fallback')),
    );
    registerFallbackValue(
      DioException(requestOptions: RequestOptions(path: '/fallback')),
    );
  });

  setUp(() {
    interceptor = DioPilotInterceptor();
  });

  group('DioPilotInterceptor', () {
    test('can be instantiated without crashing', () {
      expect(interceptor, isA<DioPilotInterceptor>());
      expect(interceptor, isA<Interceptor>());
    });

    test('multiple instances can be created without crashing', () {
      final a = DioPilotInterceptor();
      final b = DioPilotInterceptor();
      final c = DioPilotInterceptor();
      expect(a, isA<DioPilotInterceptor>());
      expect(b, isA<DioPilotInterceptor>());
      expect(c, isA<DioPilotInterceptor>());
    });

    group('onRequest', () {
      test('forwards request to handler via next', () {
        final handler = MockRequestInterceptorHandler();
        final options = RequestOptions(path: '/users', method: 'GET');

        interceptor.onRequest(options, handler);

        verify(() => handler.next(options)).called(1);
      });

      test('handles POST request', () {
        final handler = MockRequestInterceptorHandler();
        final options = RequestOptions(
          path: '/users',
          method: 'POST',
          data: {'name': 'test'},
        );

        interceptor.onRequest(options, handler);

        verify(() => handler.next(options)).called(1);
      });

      test('handles request with base URL', () {
        final handler = MockRequestInterceptorHandler();
        final options = RequestOptions(
          path: '/api/data',
          method: 'GET',
          baseUrl: 'https://example.com',
        );

        interceptor.onRequest(options, handler);

        verify(() => handler.next(options)).called(1);
      });
    });

    group('onResponse', () {
      test('forwards response to handler via next', () {
        final handler = MockResponseInterceptorHandler();
        final requestOptions = RequestOptions(path: '/users', method: 'GET');
        final response = Response<dynamic>(
          requestOptions: requestOptions,
          statusCode: 200,
          data: {'users': []},
        );

        interceptor.onResponse(response, handler);

        verify(() => handler.next(response)).called(1);
      });

      test('handles response with different status codes', () {
        final handler = MockResponseInterceptorHandler();
        final requestOptions = RequestOptions(path: '/created');
        final response = Response<dynamic>(
          requestOptions: requestOptions,
          statusCode: 201,
        );

        interceptor.onResponse(response, handler);

        verify(() => handler.next(response)).called(1);
      });
    });

    group('onError', () {
      test('forwards error to handler via next', () {
        final handler = MockErrorInterceptorHandler();
        final requestOptions = RequestOptions(path: '/fail');
        final error = DioException(
          requestOptions: requestOptions,
          message: 'Connection timeout',
          response: Response<dynamic>(
            requestOptions: requestOptions,
            statusCode: 500,
          ),
        );

        interceptor.onError(error, handler);

        verify(() => handler.next(error)).called(1);
      });

      test('handles error without response', () {
        final handler = MockErrorInterceptorHandler();
        final requestOptions = RequestOptions(path: '/no-response');
        final error = DioException(
          requestOptions: requestOptions,
          message: 'No internet connection',
        );

        interceptor.onError(error, handler);

        verify(() => handler.next(error)).called(1);
      });

      test('handles error with null message', () {
        final handler = MockErrorInterceptorHandler();
        final requestOptions = RequestOptions(path: '/null-msg');
        final error = DioException(requestOptions: requestOptions);

        interceptor.onError(error, handler);

        verify(() => handler.next(error)).called(1);
      });
    });

    group('log buffer limit', () {
      test('processing more than 50 requests does not crash', () {
        final handler = MockRequestInterceptorHandler();

        for (var i = 0; i < 60; i++) {
          final options = RequestOptions(path: '/item/$i', method: 'GET');
          interceptor.onRequest(options, handler);
        }

        verify(() => handler.next(any())).called(60);
      });

      test(
        'mixed request/response/error beyond buffer limit does not crash',
        () {
          final reqHandler = MockRequestInterceptorHandler();
          final resHandler = MockResponseInterceptorHandler();
          final errHandler = MockErrorInterceptorHandler();

          for (var i = 0; i < 20; i++) {
            final options = RequestOptions(path: '/mix/$i', method: 'GET');
            interceptor.onRequest(options, reqHandler);

            final response = Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
            );
            interceptor.onResponse(response, resHandler);

            final error = DioException(
              requestOptions: options,
              message: 'error $i',
            );
            interceptor.onError(error, errHandler);
          }

          // 20 requests + 20 responses + 20 errors = 60 total log entries
          verify(() => reqHandler.next(any())).called(20);
          verify(() => resHandler.next(any())).called(20);
          verify(() => errHandler.next(any())).called(20);
        },
      );
    });

    group('Dio integration', () {
      test('can be added to a Dio instance without crashing', () {
        final dio = Dio();
        dio.interceptors.add(interceptor);
        expect(dio.interceptors, contains(interceptor));
      });

      test('multiple interceptor instances can be added to Dio', () {
        final dio = Dio();
        final a = DioPilotInterceptor();
        final b = DioPilotInterceptor();
        dio.interceptors.addAll([a, b]);
        expect(dio.interceptors, containsAll([a, b]));
      });
    });
  });
}
