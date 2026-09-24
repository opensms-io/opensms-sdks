/**
 * The `analytics` resource: delivery and spend metrics.
 * @module
 */
import type {
  AnalyticsBreakdownRow,
  AnalyticsOverview,
  AnalyticsQuery,
  AnalyticsTimeseriesRow,
  RequestOptions,
} from '../models.js';
import { Resource, wireQuery } from './base.js';

/** Accessed as `client.analytics`. */
export class Analytics extends Resource {
  overview(query: AnalyticsQuery = {}, options?: RequestOptions): Promise<AnalyticsOverview> {
    return this.one({ method: 'GET', path: '/v1/analytics/overview', query: wireQuery(query) }, options);
  }

  byCountry(query: AnalyticsQuery = {}, options?: RequestOptions): Promise<AnalyticsBreakdownRow[]> {
    return this.array({ method: 'GET', path: '/v1/analytics/by-country', query: wireQuery(query) }, options);
  }

  byCarrier(query: AnalyticsQuery = {}, options?: RequestOptions): Promise<AnalyticsBreakdownRow[]> {
    return this.array({ method: 'GET', path: '/v1/analytics/by-carrier', query: wireQuery(query) }, options);
  }

  bySenderId(query: AnalyticsQuery = {}, options?: RequestOptions): Promise<AnalyticsBreakdownRow[]> {
    return this.array({ method: 'GET', path: '/v1/analytics/by-sender-id', query: wireQuery(query) }, options);
  }

  timeseries(query: AnalyticsQuery = {}, options?: RequestOptions): Promise<AnalyticsTimeseriesRow[]> {
    return this.array({ method: 'GET', path: '/v1/analytics/timeseries', query: wireQuery(query) }, options);
  }
}
