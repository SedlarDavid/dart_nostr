// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../../core/constants.dart';
import '../../core/utils.dart';
import 'filter.dart';

/// {@template nostr_request}
/// NostrRequest is a request to subscribe to a set of events that match a set of filters with a given [subscriptionId].
/// {@endtemplate}
class NostrRequest extends Equatable {
  /// The subscription ID of the request.
  final String? subscriptionId;

  /// A list of filters that the request will match.
  final List<NostrFilter> filters;

  /// {@macro nostr_request}
  NostrRequest({
    this.subscriptionId,
    required this.filters,
  });

  /// Serialize the request to send it to the remote relays websockets.
  String serialized() {
    final requestCopy = copyWith(
      subscriptionId: subscriptionId ?? NostrClientUtils.random64HexChars(),
    );

    String decodedFilters =
        jsonEncode(filters.map((item) => item.toMap()).toList());

    String header =
        jsonEncode([NostrConstants.request, requestCopy.subscriptionId]);

    final result =
        '${header.substring(0, header.length - 1)},${decodedFilters.substring(1, decodedFilters.length)}';

    return result;
  }

  /// Deserialize a request
  factory NostrRequest.deserialized(input) {
    assert(input.length >= 3, 'Invalid request, must have at least 3 elements');
    assert(
      input[0] == NostrConstants.request,
      'Invalid request, must start with ${NostrConstants.request}',
    );

    final subscriptionId = input[1];

    return NostrRequest(
      subscriptionId: subscriptionId,
      filters: List.generate(
        input.length - 2,
        (index) => NostrFilter.fromJson(
          input[index + 2],
        ),
      ),
    );
  }

  @override
  List<Object?> get props => [subscriptionId, filters];

  NostrRequest copyWith({
    String? subscriptionId,
    List<NostrFilter>? filters,
  }) {
    return NostrRequest(
      subscriptionId: subscriptionId ?? this.subscriptionId,
      filters: filters ?? this.filters,
    );
  }
}