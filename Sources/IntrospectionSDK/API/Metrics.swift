import Foundation

/// The view a metrics query aggregates over.
public struct MetricView: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let spans: MetricView = "spans"
    public static let conversations: MetricView = "conversations"
    public static let events: MetricView = "events"
    public static let judgements: MetricView = "judgements"
    public static let observations: MetricView = "observations"
    public static let patterns: MetricView = "patterns"
    /// File counts by creation, read from each file's current version. Requires the `files:read` scope as well.
    public static let files: MetricView = "files"
}

/// An aggregation operator.
public struct MetricAggregation: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let count: MetricAggregation = "count"
    public static let countDistinct: MetricAggregation = "count_distinct"
    public static let sum: MetricAggregation = "sum"
    public static let avg: MetricAggregation = "avg"
    public static let min: MetricAggregation = "min"
    public static let max: MetricAggregation = "max"
    public static let p50: MetricAggregation = "p50"
    public static let p75: MetricAggregation = "p75"
    public static let p90: MetricAggregation = "p90"
    public static let p95: MetricAggregation = "p95"
    public static let p99: MetricAggregation = "p99"
}

/// A pre-aggregation filter operator.
public struct MetricFilterOperator: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let eq: MetricFilterOperator = "eq"
    public static let neq: MetricFilterOperator = "neq"
    public static let gt: MetricFilterOperator = "gt"
    public static let gte: MetricFilterOperator = "gte"
    public static let lt: MetricFilterOperator = "lt"
    public static let lte: MetricFilterOperator = "lte"
    public static let `in`: MetricFilterOperator = "in"
    public static let nin: MetricFilterOperator = "nin"
    public static let exists: MetricFilterOperator = "exists"
    public static let contains: MetricFilterOperator = "contains"
}

/// A time-bucket width. `auto` lets the server pick one.
public struct MetricInterval: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let auto: MetricInterval = "auto"
    public static let oneMinute: MetricInterval = "1m"
    public static let fiveMinutes: MetricInterval = "5m"
    public static let fifteenMinutes: MetricInterval = "15m"
    public static let thirtyMinutes: MetricInterval = "30m"
    public static let oneHour: MetricInterval = "1h"
    public static let twoHours: MetricInterval = "2h"
    public static let threeHours: MetricInterval = "3h"
    public static let sixHours: MetricInterval = "6h"
    public static let twelveHours: MetricInterval = "12h"
    public static let oneDay: MetricInterval = "1d"
    public static let twoDays: MetricInterval = "2d"
    public static let oneWeek: MetricInterval = "1w"
    public static let oneMonth: MetricInterval = "1mo"
}

/// One requested metric. `count` takes no measure; every other aggregation requires one.
public struct MetricSpec: Codable, Sendable, Hashable {
    public var measure: String?
    public var aggregation: MetricAggregation

    public init(_ aggregation: MetricAggregation, measure: String? = nil) {
        self.aggregation = aggregation
        self.measure = measure
    }

    /// A `count` metric.
    public static var count: MetricSpec { MetricSpec(.count) }
}

/// A group-by dimension.
public struct MetricDimension: Codable, Sendable, Hashable {
    public var field: String

    public init(_ field: String) { self.field = field }

    /// Group the `files` view by `metadata.<key>` (key `^[a-z][a-z0-9_]{0,63}$`); a file without the key groups under `""`.
    public static func fileMetadata(_ key: String) -> MetricDimension { MetricDimension("metadata.\(key)") }
}

/// A row filter. `value` is a scalar for comparisons, an array for `in`/`nin`, and nil for `exists`.
public struct MetricFilter: Codable, Sendable, Hashable {
    public var field: String
    public var `operator`: MetricFilterOperator
    public var value: JSONValue?

    public init(_ field: String, _ operator: MetricFilterOperator, _ value: JSONValue? = nil) {
        self.field = field
        self.operator = `operator`
        self.value = value
    }

    /// `files` view rows whose `metadata.<key>` equals `value`, compared with its JSON type (`3` is not `"3"`).
    public static func fileMetadata(_ key: String, equals value: JSONValue) -> MetricFilter {
        MetricFilter("metadata.\(key)", .eq, value)
    }
}

/// Time bucketing: a `granularity` (named or `auto`) or a bucket count.
public struct MetricTimeDimension: Codable, Sendable, Hashable {
    public var granularity: MetricInterval?
    public var bins: Int?

    public init(granularity: MetricInterval? = nil, bins: Int? = nil) {
        self.granularity = granularity
        self.bins = bins
    }
}

/// What an ordering term sorts by.
public struct MetricOrderType: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let metric: MetricOrderType = "metric"
    public static let dimension: MetricOrderType = "dimension"
    public static let time: MetricOrderType = "time"
}

/// An ordering term: a metric by index, a dimension by field, or time.
public struct MetricOrderBy: Codable, Sendable, Hashable {
    public var type: MetricOrderType
    /// Server default `asc`.
    public var direction: ReadOrder?
    public var metricIndex: Int?
    public var field: String?

    public init(type: MetricOrderType, direction: ReadOrder? = nil, metricIndex: Int? = nil, field: String? = nil) {
        self.type = type
        self.direction = direction
        self.metricIndex = metricIndex
        self.field = field
    }

    public static func metric(_ index: Int, _ direction: ReadOrder? = nil) -> MetricOrderBy {
        MetricOrderBy(type: .metric, direction: direction, metricIndex: index)
    }

    public static func dimension(_ field: String, _ direction: ReadOrder? = nil) -> MetricOrderBy {
        MetricOrderBy(type: .dimension, direction: direction, field: field)
    }

    public static func time(_ direction: ReadOrder? = nil) -> MetricOrderBy {
        MetricOrderBy(type: .time, direction: direction)
    }

    private enum CodingKeys: String, CodingKey {
        case type, direction, field
        case metricIndex = "metric_index"
    }
}

/// A post-aggregation filter on a metric, by its request index.
public struct MetricHaving: Codable, Sendable, Hashable {
    public var metricIndex: Int
    /// `eq`, `neq`, `gt`, `gte`, `lt` or `lte`.
    public var `operator`: MetricFilterOperator
    public var value: Double

    public init(metricIndex: Int, _ operator: MetricFilterOperator, _ value: Double) {
        self.metricIndex = metricIndex
        self.operator = `operator`
        self.value = value
    }

    private enum CodingKeys: String, CodingKey {
        case value
        case `operator`
        case metricIndex = "metric_index"
    }
}

/// Row and series limits.
public struct MetricQueryConfig: Codable, Sendable, Hashable {
    /// 1-10000, server default 100.
    public var rowLimit: Int?
    /// 1-100; requires a time dimension and at least one dimension.
    public var seriesLimit: Int?

    public init(rowLimit: Int? = nil, seriesLimit: Int? = nil) {
        self.rowLimit = rowLimit
        self.seriesLimit = seriesLimit
    }

    private enum CodingKeys: String, CodingKey {
        case rowLimit = "row_limit"
        case seriesLimit = "series_limit"
    }
}

/// Body of `POST /v1/metrics`. The contract is closed: the server rejects unknown fields.
public struct MetricQueryRequest: Codable, Sendable, Hashable {
    public var view: MetricView
    public var metrics: [MetricSpec]
    public var dimensions: [MetricDimension]?
    public var filters: [MetricFilter]?
    public var timeDimension: MetricTimeDimension?
    public var orderBy: [MetricOrderBy]?
    public var having: [MetricHaving]?
    /// Window start (inclusive).
    public var fromTimestamp: Date
    /// Window end (exclusive).
    public var toTimestamp: Date
    public var config: MetricQueryConfig?

    public init(
        view: MetricView, metrics: [MetricSpec], from fromTimestamp: Date, to toTimestamp: Date,
        dimensions: [MetricDimension]? = nil, filters: [MetricFilter]? = nil,
        timeDimension: MetricTimeDimension? = nil, orderBy: [MetricOrderBy]? = nil, having: [MetricHaving]? = nil,
        config: MetricQueryConfig? = nil
    ) {
        self.view = view
        self.metrics = metrics
        self.fromTimestamp = fromTimestamp
        self.toTimestamp = toTimestamp
        self.dimensions = dimensions
        self.filters = filters
        self.timeDimension = timeDimension
        self.orderBy = orderBy
        self.having = having
        self.config = config
    }

    private enum CodingKeys: String, CodingKey {
        case view, metrics, dimensions, filters, having, config
        case timeDimension = "time_dimension"
        case orderBy = "order_by"
        case fromTimestamp = "from_timestamp"
        case toTimestamp = "to_timestamp"
    }
}

/// One dimension value on a result row.
public struct MetricDimensionValue: Codable, Sendable, Hashable {
    public var field: String
    public var value: String?
}

/// One metric value on a result row.
public struct MetricResultValue: Codable, Sendable, Hashable {
    public var metricIndex: Int
    public var measure: String?
    public var aggregation: MetricAggregation?
    public var value: Double?

    private enum CodingKeys: String, CodingKey {
        case measure, aggregation, value
        case metricIndex = "metric_index"
    }
}

/// One aggregated row.
public struct MetricResultRow: Codable, Sendable, Hashable {
    /// Bucket start in epoch milliseconds when the query is time-bucketed.
    public var timestamp: Int64?
    public var dimensions: [MetricDimensionValue]
    public var metrics: [MetricResultValue]

    private enum CodingKeys: String, CodingKey {
        case timestamp, dimensions, metrics
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decodeIfPresent(Int64.self, forKey: .timestamp)
        dimensions = try container.decodeIfPresent([MetricDimensionValue].self, forKey: .dimensions) ?? []
        metrics = try container.decodeIfPresent([MetricResultValue].self, forKey: .metrics) ?? []
    }

    /// The bucket start as a date.
    public var date: Date? { timestamp.map { Date(timeIntervalSince1970: Double($0) / 1000) } }

    /// The value of the metric at a request index.
    public func value(at metricIndex: Int) -> Double? {
        metrics.first { $0.metricIndex == metricIndex }?.value
    }

    /// The value of a dimension field.
    public func dimension(_ field: String) -> String? {
        dimensions.first { $0.field == field }?.value
    }
}

/// The window the server actually applied.
public struct MetricEffectiveWindow: Codable, Sendable, Hashable {
    public var start: Date?
    public var end: Date?
}

/// Metadata about an executed query.
public struct MetricQueryMeta: Codable, Sendable, Hashable {
    public var view: MetricView?
    public var window: MetricEffectiveWindow?
    public var rowCount: Int?
    public var rowLimit: Int?
    public var interval: MetricInterval?
    public var stepSeconds: Int?
    /// A percentile or open group-by used approximate state.
    public var approximate: Bool?
    /// The result hit the row or series limit.
    public var truncated: Bool?
    /// The read was confined to the caller's own owner key, not the whole project.
    public var ownerScoped: Bool?
    public var orderBy: [MetricOrderBy]?

    private enum CodingKeys: String, CodingKey {
        case view, window, interval, approximate, truncated
        case rowCount = "row_count"
        case rowLimit = "row_limit"
        case stepSeconds = "step_seconds"
        case ownerScoped = "owner_scoped"
        case orderBy = "order_by"
    }
}

/// Response of `POST /v1/metrics`.
public struct MetricQueryResponse: Codable, Sendable, Hashable {
    public var data: [MetricResultRow]
    public var meta: MetricQueryMeta?

    private enum CodingKeys: String, CodingKey {
        case data, meta
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decodeIfPresent([MetricResultRow].self, forKey: .data) ?? []
        meta = try container.decodeIfPresent(MetricQueryMeta.self, forKey: .meta)
    }
}

/// Bounded telemetry aggregation (`POST /v1/metrics`).
public struct MetricsAPI: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    /// Run one metrics query. A malformed query is a validation error.
    public func query(_ request: MetricQueryRequest) async throws -> MetricQueryResponse {
        try await http.json("POST", "/v1/metrics", body: .encode(request))
    }
}

extension DataPlaneConnection {
    /// Telemetry aggregation.
    public var metrics: MetricsAPI { MetricsAPI(http: dataPlane) }
}
