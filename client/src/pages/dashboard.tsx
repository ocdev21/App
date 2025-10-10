import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import MetricCard from "../components/metric-card";
import { AlertTriangle, BarChart3, Shield, FileText } from "lucide-react";
import type { DashboardMetrics, DashboardMetricsWithChanges, AnomalyTrend, AnomalyTypeBreakdown, SeverityBreakdown, HourlyHeatmapData, TopAffectedSource } from "@shared/schema";
import { LineChart, Line, BarChart, Bar, PieChart, Pie, Cell, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';

export default function Dashboard() {
  const { data: metricsWithChanges, isLoading: metricsLoading } = useQuery<DashboardMetricsWithChanges>({
    queryKey: ["/api/dashboard/metrics-with-changes"],
    refetchInterval: 30000, // Refetch every 30 seconds
  });

  const { data: trends } = useQuery<AnomalyTrend[]>({
    queryKey: [`/api/dashboard/trends?days=7`],
    refetchInterval: 60000, // Refetch every minute
  });

  const { data: breakdown } = useQuery<AnomalyTypeBreakdown[]>({
    queryKey: ["/api/dashboard/breakdown"],
    refetchInterval: 60000,
  });

  const { data: severityData } = useQuery<SeverityBreakdown[]>({
    queryKey: ["/api/dashboard/severity"],
    refetchInterval: 60000,
  });

  const { data: heatmapData } = useQuery<HourlyHeatmapData[]>({
    queryKey: ["/api/dashboard/heatmap?days=7"],
    refetchInterval: 60000,
  });

  const { data: topSources } = useQuery<TopAffectedSource[]>({
    queryKey: ["/api/dashboard/top-sources?limit=10"],
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
  const SEVERITY_COLORS: Record<string, string> = {
    'critical': '#ef4444',
    'high': '#f59e0b',
    'medium': '#3b82f6',
    'low': '#10b981'
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
                <LineChart data={trends} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                  <XAxis 
                    dataKey="date" 
                    stroke="#6b7280" 
                    fontSize={11}
                    tickFormatter={(value) => {
                      const date = new Date(value);
                      return `${date.getMonth() + 1}/${date.getDate()}`;
                    }}
                  />
                  <YAxis stroke="#6b7280" fontSize={12} allowDecimals={false} />
                  <Tooltip
                    contentStyle={{ backgroundColor: '#fff', border: '1px solid #e5e7eb', borderRadius: '8px' }}
                    labelStyle={{ color: '#374151', fontWeight: 600 }}
                    formatter={(value: any) => [`${value} anomalies`, 'Count']}
                    labelFormatter={(label) => {
                      const date = new Date(label);
                      return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
                    }}
                  />
                  <Line
                    type="monotone"
                    dataKey="count"
                    stroke="#3b82f6"
                    strokeWidth={3}
                    dot={{ fill: '#3b82f6', r: 5 }}
                    activeDot={{ r: 7 }}
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
              <div className="flex items-center justify-between h-full">
                <ResponsiveContainer width="60%" height="100%">
                  <PieChart>
                    <Pie
                      data={breakdown}
                      cx="50%"
                      cy="50%"
                      innerRadius={50}
                      outerRadius={90}
                      fill="#8884d8"
                      dataKey="count"
                      paddingAngle={2}
                    >
                      {breakdown.map((entry, index) => (
                        <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                      ))}
                    </Pie>
                    <Tooltip
                      contentStyle={{ backgroundColor: '#fff', border: '1px solid #e5e7eb', borderRadius: '8px', padding: '8px 12px' }}
                      formatter={(value: any, name: string, props: any) => [
                        `${value} (${props.payload.percentage}%)`,
                        props.payload.type.charAt(0).toUpperCase() + props.payload.type.slice(1).replace('_', ' ')
                      ]}
                    />
                  </PieChart>
                </ResponsiveContainer>
                <div className="flex flex-col gap-3 w-40%">
                  {breakdown.map((entry, index) => (
                    <div key={entry.type} className="flex items-center gap-3">
                      <div 
                        className="w-4 h-4 rounded" 
                        style={{ backgroundColor: COLORS[index % COLORS.length] }}
                      />
                      <div className="flex-1">
                        <div className="text-sm font-medium text-gray-900 capitalize">
                          {entry.type.replace('_', ' ')}
                        </div>
                        <div className="text-xs text-gray-500">
                          {entry.count} ({entry.percentage}%)
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ) : (
              <div className="h-full flex items-center justify-center text-gray-400">
                <p>No anomalies detected yet</p>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* New Charts Row */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        {/* Severity Breakdown */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-6">Severity Breakdown</h3>
          <div className="h-64">
            {severityData && severityData.length > 0 ? (
              <div className="flex items-center justify-between h-full">
                <ResponsiveContainer width="60%" height="100%">
                  <PieChart>
                    <Pie
                      data={severityData}
                      cx="50%"
                      cy="50%"
                      innerRadius={50}
                      outerRadius={90}
                      fill="#8884d8"
                      dataKey="count"
                      paddingAngle={2}
                    >
                      {severityData.map((entry) => (
                        <Cell key={`cell-${entry.severity}`} fill={SEVERITY_COLORS[entry.severity] || '#6b7280'} />
                      ))}
                    </Pie>
                    <Tooltip
                      contentStyle={{ backgroundColor: '#fff', border: '1px solid #e5e7eb', borderRadius: '8px', padding: '8px 12px' }}
                      formatter={(value: any, name: string, props: any) => [
                        `${value} (${props.payload.percentage}%)`,
                        props.payload.severity.charAt(0).toUpperCase() + props.payload.severity.slice(1)
                      ]}
                    />
                  </PieChart>
                </ResponsiveContainer>
                <div className="flex flex-col gap-3 w-40%">
                  {severityData.map((entry) => (
                    <div key={entry.severity} className="flex items-center gap-3">
                      <div 
                        className="w-4 h-4 rounded" 
                        style={{ backgroundColor: SEVERITY_COLORS[entry.severity] || '#6b7280' }}
                      />
                      <div className="flex-1">
                        <div className="text-sm font-medium text-gray-900 capitalize">
                          {entry.severity}
                        </div>
                        <div className="text-xs text-gray-500">
                          {entry.count} ({entry.percentage}%)
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ) : (
              <div className="h-full flex items-center justify-center text-gray-400">
                <p>No severity data available</p>
              </div>
            )}
          </div>
        </div>

        {/* Top Affected Sources */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-6">Top Affected Sources</h3>
          <div className="h-64">
            {topSources && topSources.length > 0 ? (
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={topSources} layout="vertical" margin={{ top: 5, right: 30, left: 100, bottom: 5 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                  <XAxis type="number" stroke="#6b7280" fontSize={11} />
                  <YAxis 
                    dataKey="source" 
                    type="category" 
                    stroke="#6b7280" 
                    fontSize={10}
                    width={90}
                    tickFormatter={(value) => value.length > 15 ? value.substring(0, 12) + '...' : value}
                  />
                  <Tooltip
                    contentStyle={{ backgroundColor: '#fff', border: '1px solid #e5e7eb', borderRadius: '8px' }}
                    formatter={(value: any) => [`${value} anomalies`, 'Count']}
                  />
                  <Bar dataKey="count" fill="#3b82f6" radius={[0, 4, 4, 0]} />
                </BarChart>
              </ResponsiveContainer>
            ) : (
              <div className="h-full flex items-center justify-center text-gray-400">
                <p>No source data available</p>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Hourly Heatmap */}
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-6">Hourly Anomaly Heatmap (Last 7 Days)</h3>
        <div className="h-80">
          {heatmapData && heatmapData.length > 0 ? (
            (() => {
              const filteredData = heatmapData.filter(d => d.count > 0);
              return filteredData.length > 0 ? (
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={filteredData} margin={{ top: 20, right: 30, left: 20, bottom: 5 }}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                    <XAxis 
                      dataKey="hour" 
                      stroke="#6b7280" 
                      fontSize={11}
                      label={{ value: 'Hour of Day', position: 'insideBottom', offset: -5 }}
                    />
                    <YAxis 
                      stroke="#6b7280" 
                      fontSize={11}
                      label={{ value: 'Anomaly Count', angle: -90, position: 'insideLeft' }}
                      allowDecimals={false}
                    />
                    <Tooltip
                      contentStyle={{ backgroundColor: '#fff', border: '1px solid #e5e7eb', borderRadius: '8px' }}
                      formatter={(value: any, name: string, props: any) => [`${value} anomalies`, `${props.payload.day} ${props.payload.hour}:00`]}
                    />
                    <Bar dataKey="count" fill="#8b5cf6" radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              ) : (
                <div className="h-full flex items-center justify-center text-gray-400">
                  <p>No anomalies detected in the last 7 days</p>
                </div>
              );
            })()
          ) : (
            <div className="h-full flex items-center justify-center text-gray-400">
              <p>No heatmap data available</p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
