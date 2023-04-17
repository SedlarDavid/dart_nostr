import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_nostr/nostr/model/request/request.dart';

import 'package:dart_nostr/nostr/model/event.dart';

import '../../core/registry.dart';
import '../../core/utils.dart';
import '../../model/relay.dart';
import '../../model/relay_informations.dart';
import '../../model/request/close.dart';
import 'base/relays.dart';

import 'package:http/http.dart' as http;

/// {@template nostr_relays}
/// This class is responsible for all the relays related operations.
/// {@endtemplate}
class NostrRelays implements NostrRelaysBase {
  /// This is the controller which will receive all events from all relays.
  final _streamController = StreamController<NostrEvent>.broadcast();

  /// This is the stream which will have all events from all relays.
  @override
  Stream<NostrEvent> get stream => _streamController.stream;

  /// This method is responsible for initializing the connection to all relays.
  /// It takes a [List<String>] of relays urls, then it connects to each relay and registers it for future use, if [relayUrl] is empty, it will throw an [AssertionError] since it doesn't make sense to connect to an empty list of relays.
  ///
  ///
  /// The [WebSocket]s of the relays will start being listened to get events from them immediately after calling this method, unless you set the [lazyListeningToRelays] parameter to `true`, then you will have to call the [startListeningToRelays] method to start listening to the relays manually.
  ///
  ///
  /// You can also pass a callback to the [onRelayListening] parameter to be notified when a relay starts listening to it's websocket.
  ///
  ///
  /// You can also pass a callback to the [onRelayError] parameter to be notified when a relay websocket throws an error.
  ///
  ///
  /// You can also pass a callback to the [onRelayDone] parameter to be notified when a relay websocket is closed.
  ///
  ///
  /// You will need to call this method before using any other method, as example, in your `main()` method to make sure that the connection is established before using any other method.
  /// ```dart
  /// void main() async {
  ///  await Nostr.instance.init(relaysUrl: ["wss://relay.damus.io"]);
  /// // ...
  /// runApp(MyApp()); // if it is a flutter app
  /// }
  /// ```
  ///
  /// You can also use this method to re-connect to all relays in case of a connection failure.
  @override
  Future<void> init({
    required List<String> relaysUrl,
    void Function(String relayUrl, dynamic receivedData)? onRelayListening,
    void Function(String relayUrl, Object? error)? onRelayError,
    void Function(String relayUrl)? onRelayDone,
    bool lazyListeningToRelays = false,
    bool retryOnError = false,
    bool retryOnClose = false,
    bool ensureToClearRegistriesBeforeStarting = true,
  }) async {
    assert(
      relaysUrl.isNotEmpty,
      "initiating relays with an empty list doesn't make sense, please provide at least one relay url.",
    );

    _clearRegistriesIf(ensureToClearRegistriesBeforeStarting);

    await _startConnectingAndRegisteringRelays(
      relaysUrl: relaysUrl,
      onRelayListening: onRelayListening,
      onRelayError: onRelayError,
      onRelayDone: onRelayDone,
      lazyListeningToRelays: lazyListeningToRelays,
      retryOnError: retryOnError,
      retryOnClose: retryOnClose,
    );
  }

  /// This method is responsible for sending an event to all relays that you did registered with the [init] method.
  ///
  /// It takes a [NostrEvent] object, then it serializes it internally and sends it to all relays [WebSocket]s.
  ///
  @override
  void sendEventToRelays(NostrEvent event) {
    final serialized = event.serialized();

    _runFunctionOverRelationIteration((relay) {
      relay.socket.add(serialized);
      NostrClientUtils.log(
        "event with id: ${event.id} is sent to relay with url: ${relay.url}",
      );
    });
  }

  /// This method will send a [request] to all relays that you did registered with the [init] method, and gets your a [Stream] of [NostrEvent]s that will be filtered by the [request]'s [subscriptionId] automatically.
  ///
  /// if the you do not specify a [subscriptionId] in the [request], it will be generated automatically from the library. (This is recommended only of you're not planning to use the [closeEventsSubscription] method.
  @override
  Stream<NostrEvent> startEventsSubscription({
    required NostrRequest request,
  }) {
    final serialized = request.serialized();

    _runFunctionOverRelationIteration((relay) {
      relay.socket.add(serialized);
      NostrClientUtils.log(
        "request with subscription id: ${request.subscriptionId} is sent to relay with url: ${relay.url}",
      );
    });

    return stream.where((event) {
      return event.subscriptionId == request.subscriptionId;
    });
  }

  /// This method will close the subscription of the [subscriptionId] that you passed to it.
  ///
  /// You can use after calling the [startEventsSubscription] method to close the subscription of the [subscriptionId] that you passed to it.
  @override
  void closeEventsSubscription(String subscriptionId) {
    final close = NostrRequestClose(subscriptionId: subscriptionId);
    final serialized = close.serialized();

    _runFunctionOverRelationIteration((relay) {
      relay.socket.add(serialized);
      NostrClientUtils.log(
        "close request with subscription id: $subscriptionId is sent to relay with url: ${relay.url}",
      );
    });
  }

  /// This method will start listening to all relays that you did registered with the [init] method.
  ///
  /// you need to call this method manually only if you set the [lazyListeningToRelays] parameter to `true` in the [init] method, otherwise it will be called automatically by the [init] method.
  @override
  void startListeningToRelays({
    required String relay,
    void Function(String relayUrl, dynamic receivedData)? onRelayListening,
    void Function(String relayUrl, Object? error)? onRelayError,
    void Function(String relayUrl)? onRelayDone,
    bool retryOnError = false,
    bool retryOnClose = false,
  }) {
    NostrRegistry.getRelayWebSocket(relayUrl: relay)!.listen((d) {
      if (onRelayListening != null) {
        onRelayListening(relay, d);
      }

      if (NostrEvent.canBeDeserializedEvent(d)) {
        _streamController.sink.add(NostrEvent.fromRelayMessage(d));
        NostrClientUtils.log(
            "received event with content: ${NostrEvent.fromRelayMessage(d).content} from relay: $relay");
      } else {
        NostrClientUtils.log(
            "received non-event message from relay: $relay, message: $d");
      }
    }, onError: (error) {
      if (retryOnError) {
        _reconnectToRelay(
          relay: relay,
          onRelayListening: onRelayListening,
          onRelayError: onRelayError,
          onRelayDone: onRelayDone,
          retryOnError: retryOnError,
          retryOnClose: retryOnClose,
        );
      }

      if (onRelayError != null) {
        onRelayError(relay, error);
      }
      NostrClientUtils.log(
        "web socket of relay with $relay had an error: $error",
        error,
      );
    }, onDone: () {
      if (retryOnClose) {
        _reconnectToRelay(
          relay: relay,
          onRelayListening: onRelayListening,
          onRelayError: onRelayError,
          onRelayDone: onRelayDone,
          retryOnError: retryOnError,
          retryOnClose: retryOnClose,
        );
      }

      if (onRelayDone != null) {
        onRelayDone(relay);
      }
      NostrClientUtils.log("""
web socket of relay with $relay is done:
close code: ${NostrRegistry.getRelayWebSocket(relayUrl: relay)!.closeCode}.
close reason: ${NostrRegistry.getRelayWebSocket(relayUrl: relay)!.closeReason}.
""");
    });
  }

  Future<bool> verifyNip05({
    required String internetIdentifier,
    required String pubKey,
  }) async {
    assert(
      pubKey.length == 64 || !pubKey.startsWith("npub"),
      "pub key is invalid, it must be in hex format and not a npub(nip19) key!",
    );
    assert(
      internetIdentifier.contains("@") &&
          internetIdentifier.split("@").length == 2,
      "invalid internet identifier",
    );

    try {
      final localPart = internetIdentifier.split("@")[0];
      final domainPart = internetIdentifier.split("@")[1];
      final res = await http.get(
        Uri.parse("https://$domainPart/.well-known/nostr.json?name=$localPart"),
      );

      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      assert(decoded["names"] != null, "invalid nip05 response, no names key!");
      final pubKeyFromResponse = decoded["names"][localPart];
      assert(pubKeyFromResponse != null, "invalid nip05 response, no pub key!");

      return pubKey == pubKeyFromResponse;
    } catch (e) {
      NostrClientUtils.log(
        "error while verifying nip05 for internet identifier: $internetIdentifier",
        e,
      );
      rethrow;
    }
  }

  Future<RelayInformations> relayInformationsDocumentNip11({
    required String relayUrl,
  }) async {
    try {
      final relayHttpUri = _getHttpUrlFromWebSocketUrl(relayUrl);
      final res = await http.get(
        relayHttpUri,
        headers: {
          "Accept": "application/nostr+json",
        },
      );
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;

      return RelayInformations.fromNip11Response(decoded);
    } catch (e) {
      NostrClientUtils.log(
        "error while getting relay informations from nip11 for relay url: $relayUrl",
        e,
      );

      rethrow;
    }
  }

  Uri _getHttpUrlFromWebSocketUrl(String relayUrl) {
    assert(
      relayUrl.startsWith("ws://") || relayUrl.startsWith("wss://"),
      "invalid relay url",
    );

    try {
      String removeWebsocketSign = relayUrl.replaceFirst("ws://", "");
      removeWebsocketSign = removeWebsocketSign.replaceFirst("wss://", "");
      return Uri.parse(removeWebsocketSign);
    } catch (e) {
      NostrClientUtils.log(
        "error while getting http url from websocket url: $relayUrl",
        e,
      );

      rethrow;
    }
  }

  void _runFunctionOverRelationIteration(
    Function(NostrRelay) function,
  ) {
    for (int index = 0;
        index < NostrRegistry.allRelaysEntries().length;
        index++) {
      final entries = NostrRegistry.allRelaysEntries();
      final current = entries[index];
      function(NostrRelay(url: current.key, socket: current.value));
    }
  }

  void _clearRegistriesIf(bool ensureToClearRegistriesBeforeStarting) {
    if (ensureToClearRegistriesBeforeStarting) {
      NostrRegistry.clearAllRegistries();
    }
  }

  void _reconnectToRelay({
    required String relay,
    void Function(String relayUrl, dynamic receivedData)? onRelayListening,
    void Function(String relayUrl, Object? error)? onRelayError,
    void Function(String relayUrl)? onRelayDone,
    bool retryOnError = false,
    bool retryOnClose = false,
  }) {
    NostrClientUtils.log(
      "retrying to listen to relay with url: $relay...",
    );

    startListeningToRelays(
      relay: relay,
      onRelayListening: onRelayListening,
      onRelayError: onRelayError,
      onRelayDone: onRelayDone,
      retryOnError: retryOnError,
      retryOnClose: retryOnClose,
    );
  }

  Future<void> _startConnectingAndRegisteringRelays({
    required List<String> relaysUrl,
    void Function(String relayUrl, dynamic receivedData)? onRelayListening,
    void Function(String relayUrl, Object? error)? onRelayError,
    void Function(String relayUrl)? onRelayDone,
    bool lazyListeningToRelays = false,
    bool retryOnError = false,
    bool retryOnClose = false,
  }) async {
    for (String relay in relaysUrl) {
      NostrRegistry.registerRelayWebSocket(
        relayUrl: relay,
        webSocket: await WebSocket.connect(relay),
      );
      NostrClientUtils.log(
        "the websocket for the relay with url: $relay, is registered.",
      );
      NostrClientUtils.log(
        "listening to the websocket for the relay with url: $relay...",
      );
      if (!lazyListeningToRelays) {
        startListeningToRelays(
          relay: relay,
          onRelayListening: onRelayListening,
          onRelayError: onRelayError,
          onRelayDone: onRelayDone,
          retryOnError: retryOnError,
          retryOnClose: retryOnClose,
        );
      }
    }
  }
}
