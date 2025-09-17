import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Search, ChevronDown } from "lucide-react";
import AnomalyTable from "../components/anomaly-table";
import type { Anomaly } from "@shared/schema";

export default function Anomalies() {
  const [searchTerm, setSearchTerm] = useState("");
  const [typeFilter, setTypeFilter] = useState("all");
  const [severityFilter, setSeverityFilter] = useState("all");

  const { data: anomalies = [], isLoading, refetch } = useQuery<Anomaly[]>({
    queryKey: ["/api/anomalies"],
    refetchInterval: 10000, // Refetch every 10 seconds
  });

  // Filter anomalies based on search and filters
  const filteredAnomalies = anomalies.filter((anomaly) => {
    const matchesSearch = !searchTerm || 
      anomaly.description?.toLowerCase().includes(searchTerm.toLowerCase()) ||
      anomaly.type?.toLowerCase().includes(searchTerm.toLowerCase()) ||
      anomaly.source?.toLowerCase().includes(searchTerm.toLowerCase());

    const matchesType = typeFilter === "all" || anomaly.type === typeFilter;
    const matchesSeverity = severityFilter === "all" || anomaly.severity === severityFilter;

    return matchesSearch && matchesType && matchesSeverity;
  });

  return (
    <div className="p-8 bg-gray-50 min-h-screen">
      {/* Page Header */}
      <div className="mb-8">
        <h1 className="text-2xl font-bold text-gray-900 mb-2">Anomalies</h1>
        <p className="text-gray-600">Detected network anomalies and recommendations</p>
      </div>

      {/* Search and Filters */}
      <div className="flex items-center gap-4 mb-8">
        {/* Search Bar */}
        <div className="relative flex-1 max-w-sm">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 w-4 h-4" />
          <input
            type="text"
            placeholder="Search anomalies..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full pl-10 pr-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 bg-white"
          />
        </div>

        {/* Type Filter */}
        <div className="relative">
          <select
            value={typeFilter}
            onChange={(e) => setTypeFilter(e.target.value)}
            className="appearance-none bg-white border border-gray-300 rounded-lg px-4 py-2 pr-8 focus:ring-2 focus:ring-blue-500 focus:border-blue-500 min-w-32"
          >
            <option value="all">All Types</option>
            <option value="fronthaul">Fronthaul</option>
            <option value="ue_event">UE Event</option>
            <option value="mac_address">MAC Address</option>
            <option value="protocol">Protocol</option>
          </select>
          <ChevronDown className="absolute right-2 top-1/2 transform -translate-y-1/2 text-gray-400 w-4 h-4 pointer-events-none" />
        </div>

        {/* Severity Filter */}
        <div className="relative">
          <select
            value={severityFilter}
            onChange={(e) => setSeverityFilter(e.target.value)}
            className="appearance-none bg-white border border-gray-300 rounded-lg px-4 py-2 pr-8 focus:ring-2 focus:ring-blue-500 focus:border-blue-500 min-w-36"
          >
            <option value="all">All Severities</option>
            <option value="critical">Critical</option>
            <option value="high">High</option>
            <option value="medium">Medium</option>
            <option value="low">Low</option>
          </select>
          <ChevronDown className="absolute right-2 top-1/2 transform -translate-y-1/2 text-gray-400 w-4 h-4 pointer-events-none" />
        </div>
      </div>

      {/* Detected Anomalies Section */}
      <div className="bg-white rounded-lg shadow-sm border border-gray-200">
        <div className="p-6 border-b border-gray-200">
          <h2 className="text-lg font-semibold text-gray-900 mb-2">Detected Anomalies</h2>
          <p className="text-gray-600">Recent network anomalies requiring attention</p>
        </div>

        {/* Anomaly Table */}
        <AnomalyTable 
          anomalies={filteredAnomalies} 
          isLoading={isLoading}
          showFilters={false}
        />
      </div>
    </div>
  );
}