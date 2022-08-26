import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sentry/src/client_reports/discard_reason.dart';
import 'package:sentry/src/sentry_envelope_header.dart';
import 'package:sentry/src/sentry_envelope_item_header.dart';
import 'package:sentry/src/sentry_item_type.dart';
import 'package:sentry/src/transport/data_category.dart';
import 'package:test/test.dart';
import 'package:sentry/src/sentry_tracer.dart';

import 'package:sentry/sentry.dart';

import '../mocks.dart';
import '../mocks/mock_client_report_recorder.dart';
import '../mocks/mock_hub.dart';

void main() {
  SentryEnvelope givenEnvelope() {
    final filteredEnvelopeHeader = SentryEnvelopeHeader(SentryId.empty(), null);
    final filteredItemHeader =
        SentryEnvelopeItemHeader(SentryItemType.event, () async {
      return 2;
    }, contentType: 'application/json');
    final dataFactory = () async {
      return utf8.encode('{}');
    };
    final filteredItem = SentryEnvelopeItem(filteredItemHeader, dataFactory);
    return SentryEnvelope(filteredEnvelopeHeader, [filteredItem]);
  }

  group('filter', () {
    late Fixture fixture;

    setUp(() {
      fixture = Fixture();
    });

    test('filter called', () async {
      final httpMock = MockClient((http.Request request) async {
        return http.Response('{}', 200);
      });

      fixture.options.compressPayload = false;
      final mockRateLimiter = MockRateLimiter();
      final sut = fixture.getSut(httpMock, mockRateLimiter);

      final sentryEnvelope = givenEnvelope();
      await sut.send(sentryEnvelope);

      expect(mockRateLimiter.envelopeToFilter, sentryEnvelope);
    });

    test('send filtered event', () async {
      List<int>? body;

      final httpMock = MockClient((http.Request request) async {
        body = request.bodyBytes;
        return http.Response('{}', 200);
      });

      final filteredEnvelope = givenEnvelope();

      fixture.options.compressPayload = false;
      final mockRateLimiter = MockRateLimiter()
        ..filteredEnvelope = filteredEnvelope;
      final sut = fixture.getSut(httpMock, mockRateLimiter);

      final sentryEvent = SentryEvent();
      final envelope =
          SentryEnvelope.fromEvent(sentryEvent, fixture.options.sdk);
      await sut.send(envelope);

      final envelopeData = <int>[];
      await filteredEnvelope
          .envelopeStream(fixture.options)
          .forEach(envelopeData.addAll);

      expect(body, envelopeData);
    });

    test('send nothing when filtered event null', () async {
      var httpCalled = false;
      final httpMock = MockClient((http.Request request) async {
        httpCalled = true;
        return http.Response('{}', 200);
      });

      fixture.options.compressPayload = false;
      final mockRateLimiter = MockRateLimiter()..filterReturnsNull = true;
      final sut = fixture.getSut(httpMock, mockRateLimiter);

      final sentryEvent = SentryEvent();
      final envelope =
          SentryEnvelope.fromEvent(sentryEvent, fixture.options.sdk);
      final eventId = await sut.send(envelope);

      expect(eventId, SentryId.empty());
      expect(httpCalled, false);
    });
  });

  group('updateRetryAfterLimits', () {
    late Fixture fixture;

    setUp(() {
      fixture = Fixture();
    });

    test('retryAfterHeader', () async {
      final httpMock = MockClient((http.Request request) async {
        return http.Response('{}', 429, headers: {'Retry-After': '1'});
      });
      final mockRateLimiter = MockRateLimiter();
      final sut = fixture.getSut(httpMock, mockRateLimiter);

      final sentryEvent = SentryEvent();
      final envelope =
          SentryEnvelope.fromEvent(sentryEvent, fixture.options.sdk);
      await sut.send(envelope);

      expect(mockRateLimiter.envelopeToFilter?.header.eventId,
          sentryEvent.eventId);

      expect(mockRateLimiter.errorCode, 429);
      expect(mockRateLimiter.retryAfterHeader, '1');
      expect(mockRateLimiter.sentryRateLimitHeader, isNull);
    });

    test('sentryRateLimitHeader', () async {
      final httpMock = MockClient((http.Request request) async {
        return http.Response('{}', 200,
            headers: {'X-Sentry-Rate-Limits': 'fixture-sentryRateLimitHeader'});
      });
      final mockRateLimiter = MockRateLimiter();
      final sut = fixture.getSut(httpMock, mockRateLimiter);

      final sentryEvent = SentryEvent();
      final envelope =
          SentryEnvelope.fromEvent(sentryEvent, fixture.options.sdk);
      await sut.send(envelope);

      expect(mockRateLimiter.errorCode, 200);
      expect(mockRateLimiter.retryAfterHeader, isNull);
      expect(mockRateLimiter.sentryRateLimitHeader,
          'fixture-sentryRateLimitHeader');
    });
  });

  group('client reports', () {
    late Fixture fixture;

    setUp(() {
      fixture = Fixture();
    });

    test('does records lost event for error >= 400', () async {
      final httpMock = MockClient((http.Request request) async {
        return http.Response('{}', 400);
      });
      final sut = fixture.getSut(httpMock, MockRateLimiter());

      final sentryEvent = SentryEvent();
      final envelope =
          SentryEnvelope.fromEvent(sentryEvent, fixture.options.sdk);
      await sut.send(envelope);

      expect(fixture.clientReportRecorder.reason, DiscardReason.networkError);
      expect(fixture.clientReportRecorder.category, DataCategory.error);
    });

    test('does not record lost event for error 429', () async {
      final httpMock = MockClient((http.Request request) async {
        return http.Response('{}', 429);
      });
      final sut = fixture.getSut(httpMock, MockRateLimiter());

      final sentryEvent = SentryEvent();
      final envelope =
          SentryEnvelope.fromEvent(sentryEvent, fixture.options.sdk);
      await sut.send(envelope);

      expect(fixture.clientReportRecorder.reason, null);
      expect(fixture.clientReportRecorder.category, null);
    });

    test('does record lost event for error >= 500', () async {
      final httpMock = MockClient((http.Request request) async {
        return http.Response('{}', 500);
      });
      final sut = fixture.getSut(httpMock, MockRateLimiter());

      final sentryEvent = SentryEvent();
      final envelope =
          SentryEnvelope.fromEvent(sentryEvent, fixture.options.sdk);
      await sut.send(envelope);

      expect(fixture.clientReportRecorder.reason, DiscardReason.networkError);
      expect(fixture.clientReportRecorder.category, DataCategory.error);
    });
  });

  group('feature flags', () {
    late Fixture fixture;

    setUp(() {
      fixture = Fixture();
    });

    test('parses the feature flag list', () async {
      final featureFlagsFile = File('test_resources/feature_flags.json');
      final featureFlagsJson = await featureFlagsFile.readAsString();

      final httpMock = MockClient((http.Request request) async {
        return http.Response(featureFlagsJson, 200, headers: {});
      });
      final mockRateLimiter = MockRateLimiter();
      final sut = fixture.getSut(httpMock, mockRateLimiter);

      final flags = await sut.fetchFeatureFlags();

      // accessToProfiling
      final accessToProfiling = flags!['accessToProfiling']!;

      // expect(accessToProfiling.tags['isEarlyAdopter'], 'true');

      final rollout = accessToProfiling.evaluations.first;
      expect(rollout.percentage, 0.5);
      expect(rollout.result, true);
      expect(rollout.tags['userSegment'], 'slow');
      expect(rollout.type, EvaluationType.rollout);
      expect(rollout.payload, isNull);

      final match = accessToProfiling.evaluations.last;
      expect(match.percentage, isNull);
      expect(match.result, true);
      expect(match.tags['isSentryDev'], 'true');
      expect(match.type, EvaluationType.match);
      expect(
          match.payload!['background_image'], 'https://example.com/modus1.png');

      // profilingEnabled
      final profilingEnabled = flags['profilingEnabled']!;

      // expect(profilingEnabled.tags.isEmpty, true);

      final rolloutProfiling = profilingEnabled.evaluations.first;
      expect(rolloutProfiling.percentage, 0.05);
      expect(rolloutProfiling.result, true);
      expect(rolloutProfiling.tags['isSentryDev'], 'true');
      expect(rolloutProfiling.type, EvaluationType.rollout);
      expect(rolloutProfiling.payload, isNull);

      final matchProfiling = profilingEnabled.evaluations.last;
      expect(matchProfiling.percentage, isNull);
      expect(matchProfiling.result, true);
      expect(matchProfiling.tags.isEmpty, true);
      expect(matchProfiling.type, EvaluationType.match);
      expect(matchProfiling.payload, isNull);
    }, onPlatform: {
      'browser': Skip()
    }); // TODO: web does not have File/readAsString
  });
}

class Fixture {
  final options = SentryOptions(
    dsn: 'https://public:secret@sentry.example.com/1',
  );

  late var clientReportRecorder = MockClientReportRecorder();

  HttpTransport getSut(http.Client client, RateLimiter rateLimiter) {
    options.httpClient = client;
    options.recorder = clientReportRecorder;
    return HttpTransport(options, rateLimiter);
  }

  SentryTracer createTracer({
    bool? sampled,
  }) {
    final context = SentryTransactionContext(
      'name',
      'op',
      sampled: sampled,
    );
    return SentryTracer(context, MockHub());
  }
}
