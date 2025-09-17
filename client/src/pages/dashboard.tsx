import { useQuery } from "@tanstack/react-query";
import MetricCard from "../components/metric-card";
import { AlertTriangle, BarChart3, Shield, FileText } from "lucide-react";
import type { DashboardMetrics, DashboardMetricsWithChanges, AnomalyTrend, AnomalyTypeBreakdown } from "@shared/schema";

export default function Dashboard() {
  const { data: metricsWithChanges, isLoading: metricsLoading } = useQuery<DashboardMetricsWithChanges>({
    queryKey: ["/api/dashboard/metrics-with-changes"],
    refetchInterval: 30000, // Refetch every 30 seconds
  });

  const { data: trends } = useQuery<AnomalyTrend[]>({
    queryKey: ["/api/dashboard/trends"],
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
          value={metricsWithChanges?.totalAnomalies || 5}
          change="+15.0%"
          changeType="negative"
          icon={AlertTriangle}
          iconColor="red"
        />
        <MetricCard
          title="SESSIONS ANALYZED"
          value={0}
          change="+8.3%"
          changeType="positive"
          icon={BarChart3}
          iconColor="blue"
        />
        <MetricCard
          title="DETECTION RATE"
          value="0%"
          change="-2.1%"
          changeType="negative"
          icon={Shield}
          iconColor="green"
        />
        <MetricCard
          title="FILES PROCESSED"
          value={0}
          change="+12.5%"
          changeType="positive"
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
            <div className="flex items-center space-x-4 text-sm">
              <span className="text-gray-500">This week</span>
              <span className="text-gray-900 font-medium">Last 7 days</span>
            </div>
          </div>
          <div className="h-64 flex items-center justify-center text-gray-400">
            <div className="text-center">
              <div className="w-full h-32 bg-gray-50 rounded-lg mb-4"></div>
            </div>
          </div>
        </div>

        {/* Anomaly Types Breakdown */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-6">Anomaly Types</h3>
          <div className="h-64 flex items-center justify-center">
            <p className="text-gray-400">No anomalies detected yet</p>
          </div>
        </div>
      </div>
    </div>
  );
}
