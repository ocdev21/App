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
        {/* Table Header */}
        <div className="grid grid-cols-6 gap-4 px-6 py-4 border-b border-gray-200 bg-gray-50">
          <div className="font-medium text-gray-900">Timestamp</div>
          <div className="font-medium text-gray-900">Type</div>
          <div className="font-medium text-gray-900 col-span-2">Description</div>
          <div className="font-medium text-gray-900">Source</div>
          <div className="font-medium text-gray-900">Actions</div>
        </div>

        {/* Table Body */}
        <div className="divide-y divide-gray-200">
          {anomalies.length === 0 ? (
            <div className="px-6 py-12 text-center text-gray-500 col-span-6">
              No anomalies found matching your criteria.
            </div>
          ) : (
            anomalies.map((anomaly, index) => (
              <div key={`${anomaly.timestamp}-${index}`} className="grid grid-cols-6 gap-4 px-6 py-4 hover:bg-gray-50 transition-colors">
                <div className="text-sm text-gray-900">
                  {formatTimestamp(anomaly.timestamp)}
                </div>
                <div className="flex items-center">
                  <div className={getBadgeColor(anomaly.type)}>
                    {getTypeIcon(anomaly.type)}
                    {getTypeLabel(anomaly.type)}
                  </div>
                </div>
                <div className="text-sm text-gray-900 col-span-2">
                  {anomaly.description}
                  {anomaly.packet_id && (
                    <div className="text-blue-600 text-xs mt-1">
                      packet #{anomaly.packet_id}
                    </div>
                  )}
                </div>
                <div className="text-sm text-gray-600">
                  {anomaly.source || anomaly.source_file}
                </div>
                <div className="flex items-center space-x-2">
                  <button
                    onClick={() => handleGetRecommendations(anomaly)}
                    className="px-3 py-1 text-xs bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors"
                  >
                    Get Recommendations
                  </button>
                  <button
                    onClick={() => handleGetDetails(anomaly)}
                    className="px-3 py-1 text-xs bg-gray-600 text-white rounded-md hover:bg-gray-700 transition-colors"
                  >
                    Details
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
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