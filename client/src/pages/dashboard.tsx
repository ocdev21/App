import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import MetricCard from "../components/metric-card";
import { AlertTriangle, BarChart3, Shield, FileText } from "lucide-react";
import type { DashboardMetrics, DashboardMetricsWithChanges, AnomalyTrend, AnomalyTypeBreakdown } from "@shared/schema";
import { LineChart, Line, BarChart, Bar, PieChart, Pie, Cell, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';

type TimeRange = '1h' | '24h' | '7d' | '30d';

export default function Dashboard() {
  const [timeRange, setTimeRange] = useState<TimeRange>('7d');

  const { data: metricsWithChanges, isLoading: metricsLoading } = useQuery<DashboardMetricsWithChanges>({
    queryKey: ["/api/dashboard/metrics-with-changes"],
    refetchInterval: 30000, // Refetch every 30 seconds
  });

  const { data: trends } = useQuery<AnomalyTrend[]>({
    queryKey: ["/api/dashboard/trends", timeRange],
    refetchInterval: 60000, // Refetch every minute
  });

  const { data: breakdown } = useQuery<AnomalyTypeBreakdown[]>({
    queryKey: ["/api/dashboard/breakdown"],
    refetchInterval: 60000,
  });

  if (metricsLoading) {
    return (
      <div className="p-8">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
          {[...Array(4)].map((_, i) => (
            <div key={i} className="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
              <div className="animate-pulse">
                <div className="h-4 bg-slate-200 rounded w-3/4 mb-4"></div>
                <div className="h-8 bg-slate-200 rounded w-1/2 mb-2"></div>
                <div className="h-3 bg-slate-200 rounded w-2/3"></div>
              </div>
            </div>
          ))}
        </div>
      </div>
    );
  }

  const formatChangeValue = (value: number | undefined) => {
    if (value === undefined || value === null) return "+0.0%";
    const sign = value >= 0 ? "+" : "";
    return `${sign}${value.toFixed(1)}%`;
  };

  const COLORS = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6'];

  const timeRangeLabels: Record<TimeRange, string> = {
    '1h': 'Last Hour',
    '24h': 'Last 24 Hours',
    '7d': 'Last 7 Days',
    '30d': 'Last 30 Days'
  };

  return (
    <div className="p-8 bg-gray-50 min-h-screen">
      <div className="mb-8">
        <h1 className="text-2xl font-bold text-gray-900 mb-2">Dashboard</h1>
        <p className="text-gray-600">Network anomaly detection and analysis</p>
      </div>

      {/* Metrics Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
        <MetricCard
          title="TOTAL ANOMALIES"
          value={metricsWithChanges?.totalAnomalies || 0}
          change={formatChangeValue(metricsWithChanges?.totalAnomaliesChange)}
          changeType={metricsWithChanges?.totalAnomaliesChange && metricsWithChanges.totalAnomaliesChange < 0 ? "positive" : "negative"}
          icon={AlertTriangle}
          iconColor="red"
        />
        <MetricCard
          title="SESSIONS ANALYZED"
          value={metricsWithChanges?.sessionsAnalyzed || 0}
          change={formatChangeValue(metricsWithChanges?.sessionsAnalyzedChange)}
          changeType={metricsWithChanges?.sessionsAnalyzedChange && metricsWithChanges.sessionsAnalyzedChange >= 0 ? "positive" : "negative"}
          icon={BarChart3}
          iconColor="blue"
        />
        <MetricCard
          title="DETECTION RATE"
          value={`${metricsWithChanges?.detectionRate || 0}%`}
          change={formatChangeValue(metricsWithChanges?.detectionRateChange)}
          changeType={metricsWithChanges?.detectionRateChange && metricsWithChanges.detectionRateChange >= 0 ? "positive" : "negative"}
          icon={Shield}
          iconColor="green"
        />
        <MetricCard
          title="FILES PROCESSED"
          value={metricsWithChanges?.filesProcessed || 0}
          change={formatChangeValue(metricsWithChanges?.filesProcessedChange)}
          changeType={metricsWithChanges?.filesProcessedChange && metricsWithChanges.filesProcessedChange >= 0 ? "positive" : "negative"}
          icon={FileText}
          iconColor="purple"
        />
      </div>

      {/* Charts Row */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Anomaly Trends Chart */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <div className="flex items-center justify-between mb-6">
            <h3 className="text-lg font-semibold text-gray-900">Anomaly Trends</h3>
            <div className="flex items-center space-x-2 text-sm">
              <div className="w-3 h-3 bg-blue-500 rounded"></div>
              <span className="text-gray-600">Anomalies Over Time</span>
            </div>
          </div>
          <div className="h-64">
            {trends && trends.length > 0 ? (
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={trends}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                  <XAxis dataKey="date" stroke="#6b7280" fontSize={12} />
                  <YAxis stroke="#6b7280" fontSize={12} />
                  <Tooltip
                    contentStyle={{ backgroundColor: '#fff', border: '1px solid #e5e7eb', borderRadius: '8px' }}
                    labelStyle={{ color: '#374151', fontWeight: 600 }}
                  />
                  <Line
                    type="monotone"
                    dataKey="count"
                    stroke="#3b82f6"
                    strokeWidth={2}
                    dot={{ fill: '#3b82f6', r: 4 }}
                    activeDot={{ r: 6 }}
                  />
                </LineChart>
              </ResponsiveContainer>
            ) : (
              <div className="h-full flex items-center justify-center text-gray-400">
                <p>No trend data available</p>
              </div>
            )}
          </div>
        </div>

        {/* Anomaly Types Breakdown */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-6">Anomaly Types Distribution</h3>
          <div className="h-64">
            {breakdown && breakdown.length > 0 ? (
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie
                    data={breakdown}
                    cx="50%"
                    cy="50%"
                    labelLine={false}
                    label={({ type, percentage }) => `${type}: ${percentage}%`}
                    outerRadius={80}
                    fill="#8884d8"
                    dataKey="count"
                  >
                    {breakdown.map((entry, index) => (
                      <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip
                    contentStyle={{ backgroundColor: '#fff', border: '1px solid #e5e7eb', borderRadius: '8px' }}
                  />
                </PieChart>
              </ResponsiveContainer>
            ) : (
              <div className="h-full flex items-center justify-center text-gray-400">
                <p>No anomalies detected yet</p>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
