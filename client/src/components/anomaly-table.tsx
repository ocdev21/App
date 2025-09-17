import { useState } from "react";
import { AlertTriangle, Smartphone, Network, Shield } from "lucide-react";
import { RecommendationsPopup } from "./RecommendationsPopup";
import { ExplainableAIModal } from "./ExplainableAIModal";
import type { Anomaly } from "@shared/schema";

interface AnomalyTableProps {
  anomalies: Anomaly[];
  isLoading: boolean;
  showFilters?: boolean;
}

export default function AnomalyTable({ anomalies, isLoading, showFilters = true }: AnomalyTableProps) {
  const [selectedAnomaly, setSelectedAnomaly] = useState<Anomaly | null>(null);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [selectedAnomalyForDetails, setSelectedAnomalyForDetails] = useState<Anomaly | null>(null);
  const [isDetailsModalOpen, setIsDetailsModalOpen] = useState(false);

  const getTypeIcon = (type: string) => {
    switch (type) {
      case "fronthaul":
        return <AlertTriangle className="w-4 h-4 mr-1" />;
      case "ue_event":
        return <Smartphone className="w-4 h-4 mr-1" />;
      case "mac_address":
        return <Network className="w-4 h-4 mr-1" />;
      case "protocol":
        return <Shield className="w-4 h-4 mr-1" />;
      default:
        return <AlertTriangle className="w-4 h-4 mr-1" />;
    }
  };

  const getTypeLabel = (type: string) => {
    switch (type) {
      case "fronthaul":
        return "Fronthaul";
      case "ue_event":
        return "UE Event";
      case "mac_address":
        return "MAC Address";
      case "protocol":
        return "Protocol";
      default:
        return type;
    }
  };

  const getBadgeColor = (type: string) => {
    switch (type) {
      case "fronthaul":
        return "type-badge fronthaul";
      case "ue_event":
        return "type-badge ue_event";
      case "mac_address":
        return "type-badge mac_address";
      case "protocol":
        return "type-badge protocol";
      default:
        return "type-badge";
    }
  };

  const formatTimestamp = (timestamp: string | Date) => {
    const date = new Date(timestamp);
    return date.toLocaleDateString('en-US', {
      month: 'numeric',
      day: 'numeric', 
      year: 'numeric'
    }) + ', ' + date.toLocaleTimeString('en-US', {
      hour: 'numeric',
      minute: '2-digit',
      hour12: true
    });
  };

  const handleGetRecommendations = (anomaly: Anomaly) => {
    setSelectedAnomaly(anomaly);
    setIsModalOpen(true);
  };

  const handleGetDetails = (anomaly: Anomaly) => {
    setSelectedAnomalyForDetails(anomaly);
    setIsDetailsModalOpen(true);
  };

  if (isLoading) {
    return (
      <div className="p-6">
        <div className="animate-pulse">
          <div className="space-y-3">
            {[...Array(5)].map((_, i) => (
              <div key={i} className="h-16 bg-slate-200 rounded"></div>
            ))}
          </div>
        </div>
      </div>
    );
  }

  return (
    <>
      <div className="overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Timestamp
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Type
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Description
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Source
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Severity
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {anomalies.length === 0 ? (
              <tr>
                <td colSpan={6} className="px-6 py-12 text-center text-gray-500">
                  No anomalies found matching your criteria.
                </td>
              </tr>
            ) : (
              anomalies.map((anomaly, index) => (
                <tr key={`${anomaly.timestamp}-${index}`} className="hover:bg-gray-50 transition-colors">
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {formatTimestamp(anomaly.timestamp)}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className={getBadgeColor(anomaly.type)}>
                      {getTypeIcon(anomaly.type)}
                      {getTypeLabel(anomaly.type)}
                    </div>
                  </td>
                  <td className="px-6 py-4 text-sm text-gray-900">
                    <div>
                      {anomaly.description}
                      {anomaly.packet_number && (
                        <div className="text-blue-600 text-xs mt-1">
                          Packet #{anomaly.packet_number}
                        </div>
                      )}
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                    {anomaly.source_file}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
                      anomaly.severity === 'critical' 
                        ? 'bg-red-100 text-red-800' 
                        : anomaly.severity === 'high'
                        ? 'bg-orange-100 text-orange-800'
                        : anomaly.severity === 'medium'
                        ? 'bg-yellow-100 text-yellow-800'
                        : 'bg-green-100 text-green-800'
                    }`}>
                      {anomaly.severity?.charAt(0).toUpperCase() + anomaly.severity?.slice(1) || 'Unknown'}
                    </span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium">
                    <div className="flex items-center space-x-2">
                      <button
                        onClick={() => handleGetRecommendations(anomaly)}
                        className="inline-flex items-center px-3 py-2 text-xs font-medium text-white bg-blue-600 border border-transparent rounded-md shadow-sm hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 transition-all duration-200"
                      >
                        Get Recommendations
                      </button>
                      <button
                        onClick={() => handleGetDetails(anomaly)}
                        className="inline-flex items-center px-3 py-2 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded-md shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 transition-all duration-200"
                      >
                        Details
                      </button>
                    </div>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {/* Modals */}
      {selectedAnomaly && (
        <RecommendationsPopup
          anomaly={selectedAnomaly}
          isOpen={isModalOpen}
          onClose={() => {
            setIsModalOpen(false);
            setSelectedAnomaly(null);
          }}
        />
      )}

      {selectedAnomalyForDetails && (
        <ExplainableAIModal
          anomaly={selectedAnomalyForDetails}
          isOpen={isDetailsModalOpen}
          onClose={() => {
            setIsDetailsModalOpen(false);
            setSelectedAnomalyForDetails(null);
          }}
        />
      )}
    </>
  );
}