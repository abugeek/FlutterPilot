// Explicit, versioned price configuration (task 04 §11).
//
// The old cost line matched a model id by substring ("sonnet", "haiku",
// "opus") and fell back to Sonnet prices for anything else, so an unknown
// model was silently billed at Sonnet's rate. A price is not a default; it is
// a fact that has to be supplied and dated. This module reads an explicit
// `pricing.json`, prices only the models named in it, and reports "unknown"
// for everything else. Raw token counts are unaffected — only the cost line
// is, and a cost-bounded run refuses to start without a price.
library;

import 'dart:convert';
import 'dart:io';

import 'agent.dart';

/// USD per million tokens for one model, all four billed token kinds explicit.
class ModelPrice {
  const ModelPrice({
    required this.inputPerMTok,
    required this.outputPerMTok,
    required this.cacheReadPerMTok,
    required this.cacheWritePerMTok,
  });

  final double inputPerMTok;
  final double outputPerMTok;
  final double cacheReadPerMTok;
  final double cacheWritePerMTok;

  Map<String, Object?> toJson() => {
    'input': inputPerMTok,
    'output': outputPerMTok,
    'cacheRead': cacheReadPerMTok,
    'cacheWrite': cacheWritePerMTok,
  };

  static ModelPrice fromJson(Map<String, dynamic> json) => ModelPrice(
    inputPerMTok: _money(json, 'input'),
    outputPerMTok: _money(json, 'output'),
    cacheReadPerMTok: _money(json, 'cacheRead'),
    cacheWritePerMTok: _money(json, 'cacheWrite'),
  );

  static double _money(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! num || value < 0) {
      throw FormatException('price "$key" must be a non-negative number');
    }
    return value.toDouble();
  }
}

/// The committed pricing configuration. Unknown models are simply absent; there
/// is deliberately no fallback.
class PricingConfig {
  const PricingConfig({
    required this.version,
    required this.asOf,
    required this.currency,
    required this.models,
    this.source = '<none>',
  });

  /// An empty table: every model is unknown, so no cost is reported and a
  /// cost-bounded run refuses to start until prices are supplied.
  static const empty = PricingConfig(
    version: 0,
    asOf: '',
    currency: 'USD',
    models: {},
    source: '<empty>',
  );

  final int version;

  /// The date the prices were read from the provider's published list.
  final String asOf;
  final String currency;
  final Map<String, ModelPrice> models;

  /// Where the table was loaded from (a path), for the report's provenance.
  final String source;

  ModelPrice? priceFor(String model) => models[model];

  bool knows(String model) => models.containsKey(model);

  String get versionTag => version == 0 ? 'none' : 'v$version ($asOf)';

  Map<String, Object?> toJson() => {
    'version': version,
    'asOf': asOf,
    'currency': currency,
    'source': source,
    'models': {
      for (final entry in models.entries) entry.key: entry.value.toJson(),
    },
  };

  /// Parses [text]. Throws [FormatException] on anything malformed: a bad
  /// price must not be mistaken for an unknown one.
  static PricingConfig parse(String text, {String source = '<text>'}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw FormatException('pricing is not valid JSON: ${e.message}');
    }
    if (decoded is! Map) {
      throw const FormatException('pricing must be a JSON object');
    }
    final json = decoded.cast<String, dynamic>();
    final version = json['version'];
    if (version is! int) {
      throw const FormatException('pricing needs an int "version"');
    }
    final models = json['models'];
    if (models is! Map) {
      throw const FormatException('pricing needs a "models" object');
    }
    final parsed = <String, ModelPrice>{};
    for (final entry in models.entries) {
      final id = '${entry.key}';
      if (id.isEmpty || id == 'null') {
        throw const FormatException('a pricing model id is empty');
      }
      if (entry.value is! Map) {
        throw FormatException('price for "$id" is not an object');
      }
      parsed[id] = ModelPrice.fromJson(
        (entry.value as Map).cast<String, dynamic>(),
      );
    }
    return PricingConfig(
      version: version,
      asOf: '${json['asOf'] ?? ''}',
      currency: '${json['currency'] ?? 'USD'}',
      models: parsed,
      source: source,
    );
  }

  static PricingConfig load(File file) {
    if (!file.existsSync()) {
      throw FormatException('pricing file not found: ${file.path}');
    }
    return parse(file.readAsStringSync(), source: file.path);
  }
}

/// The cost of a set of runs, or an explicit unknown.
class CostEstimate {
  const CostEstimate.known(this.usd) : known = true;
  const CostEstimate.unknown() : usd = 0, known = false;

  final double usd;
  final bool known;

  @override
  String toString() => known ? '\$${usd.toStringAsFixed(4)}' : 'unknown';
}

/// Prices [runs] with [pricing]. Returns an unknown estimate when [model] has
/// no explicit price — never a fallback.
CostEstimate estimateCost(
  String model,
  Iterable<AgentRun> runs,
  PricingConfig pricing,
) {
  final price = pricing.priceFor(model);
  if (price == null) return const CostEstimate.unknown();
  var total = 0.0;
  for (final run in runs) {
    total +=
        run.inputTokens / 1e6 * price.inputPerMTok +
        run.outputTokens / 1e6 * price.outputPerMTok +
        run.cacheReadTokens / 1e6 * price.cacheReadPerMTok +
        run.cacheWriteTokens / 1e6 * price.cacheWritePerMTok;
  }
  return CostEstimate.known(total);
}
