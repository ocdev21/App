import { useState, useRef, useEffect } from "react";
import { AlertTriangle, Smartphone, Network, Shield, ChevronDown, ChevronUp, Brain, Loader2 } from "lucide-react";
import { ExplainableAIModal } from "./ExplainableAIModal";
import type { Anomaly } from "@shared/schema";

interface AnomalyTableProps {
  anomalies: Anomaly[];
  isLoading: boolean;
  showFilters?: boolean;
  selectedAnomalies?: Set<string>;
  onSelectAll?: (checked: boolean) => void;
  onSelectAnomaly?: (id: string, checked: boolean) => void;
}

export default function AnomalyTable({ 
  anomalies, 
  isLoading, 
  showFilters = true,
  selectedAnomalies,
  onSelectAll,
  onSelectAnomaly
}: AnomalyTableProps) {
  const [expandedAnomalyId, setExpandedAnomalyId] = useState<string | null>(null);
  const [recommendations, setRecommendations] = useState<string>('');
  const [isStreaming, setIsStreaming] = useState(false);
  const [streamError, setStreamError] = useState<string | null>(null);
  const [selectedAnomalyForDetails, setSelectedAnomalyForDetails] = useState<Anomaly | null>(null);
  const [isDetailsModalOpen, setIsDetailsModalOpen] = useState(false);
  const wsRef = useRef<WebSocket | null>(null);
  const activeAnomalyIdRef = useRef<string | null>(null);
  
  const hasSelection = selectedAnomalies && onSelectAll && onSelectAnomaly;
  const allSelected = hasSelection && anomalies.length > 0 && anomalies.every(a => selectedAnomalies.has(a.id));

  // Cleanup WebSocket on unmount
  useEffect(() => {
    return () => {
      if (wsRef.current) {
        wsRef.current.close();
      }
    };
  }, []);

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

  const toggleRecommendations = (anomaly: Anomaly) => {
    if (expandedAnomalyId === anomaly.id) {
      // Collapse
      setExpandedAnomalyId(null);
      activeAnomalyIdRef.current = null;
      setRecommendations('');
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }
    } else {
      // Close any existing WebSocket before opening a new one
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }

      // Expand and fetch recommendations
      setExpandedAnomalyId(anomaly.id);
      activeAnomalyIdRef.current = anomaly.id;
      setRecommendations('');
      setStreamError(null);
      setIsStreaming(true);
      
      // Connect to WebSocket (port configurable via VITE_WS_PORT, defaults to 6080)
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      const wsPort = import.meta.env.VITE_WS_PORT || '6080';
      const wsUrl = `${protocol}//${window.location.hostname}:${wsPort}/ws`;
      
      console.log('Connecting to WebSocket:', wsUrl);
      const ws = new WebSocket(wsUrl);
      wsRef.current = ws;

      ws.onopen = () => {
        console.log('WebSocket connected for recommendations');
        ws.send(JSON.stringify({
          type: 'get_recommendations',
          anomalyId: anomaly.id
        }));
      };

      ws.onmessage = (event) => {
        // Only process messages if this WebSocket is still the active one
        if (ws !== wsRef.current) return;
        // Only process messages if this anomaly is still expanded
        if (activeAnomalyIdRef.current !== anomaly.id) return;
        
        try {
          const message = JSON.parse(event.data);
          
          switch (message.type) {
            case 'recommendation_chunk':
              setRecommendations(prev => prev + message.data);
              break;
              
            case 'recommendation_complete':
              setIsStreaming(false);
              console.log('Recommendations complete');
              break;
              
            case 'error':
              setStreamError(message.data);
              setIsStreaming(false);
              break;
          }
        } catch (err) {
          console.error('WebSocket message parse error:', err);
          setStreamError('Failed to parse recommendation response');
          setIsStreaming(false);
        }
      };

      ws.onerror = (error) => {
        // Only update state if this is still the active WebSocket
        if (ws !== wsRef.current) return;
        
        console.error('WebSocket error:', error);
        setStreamError('Connection error. Please try again.');
        setIsStreaming(false);
      };

      ws.onclose = () => {
        // Only update state if this is still the active WebSocket
        if (ws !== wsRef.current) return;
        
        console.log('WebSocket closed');
        setIsStreaming(false);
      };
    }
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
          <thead className="bg-gradient-to-r from-blue-50 to-indigo-50">
            <tr>
              {hasSelection && (
                <th className="px-4 py-4 text-left w-12">
                  <input
                    type="checkbox"
                    checked={allSelected || false}
                    onChange={(e) => onSelectAll?.(e.target.checked)}
                    className="w-4 h-4 text-blue-600 border-gray-300 rounded focus:ring-blue-500"
                  />
                </th>
              )}
              <th className="px-6 py-4 text-left text-xs font-semibold text-gray-700 uppercase tracking-wider w-44">
                Timestamp
              </th>
              <th className="px-6 py-4 text-left text-xs font-semibold text-gray-700 uppercase tracking-wider w-36">
                Type
              </th>
              <th className="px-6 py-4 text-left text-xs font-semibold text-gray-700 uppercase tracking-wider">
                Description
              </th>
              <th className="px-6 py-4 text-left text-xs font-semibold text-gray-700 uppercase tracking-wider w-56">
                Source
              </th>
              <th className="px-6 py-4 text-left text-xs font-semibold text-gray-700 uppercase tracking-wider w-28">
                Severity
              </th>
              <th className="px-6 py-4 text-left text-xs font-semibold text-gray-700 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-100">
            {anomalies.length === 0 ? (
              <tr>
                <td colSpan={hasSelection ? 7 : 6} className="px-6 py-12 text-center text-gray-500">
                  No anomalies found matching your criteria.
                </td>
              </tr>
            ) : (
              anomalies.map((anomaly, index) => (
                <>
                  {/* Main Row */}
                  <tr key={`${anomaly.timestamp}-${index}`} className={`hover:bg-blue-50/30 transition-all duration-150 ${expandedAnomalyId === anomaly.id ? 'bg-blue-50' : ''}`}>
                    {hasSelection && (
                      <td className="px-4 py-5">
                        <input
                          type="checkbox"
                          checked={selectedAnomalies?.has(anomaly.id) || false}
                          onChange={(e) => onSelectAnomaly?.(anomaly.id, e.target.checked)}
                          className="w-4 h-4 text-blue-600 border-gray-300 rounded focus:ring-blue-500"
                        />
                      </td>
                    )}
                    <td className="px-6 py-5 whitespace-nowrap text-sm font-medium text-gray-900">
                      {formatTimestamp(anomaly.timestamp)}
                    </td>
                    <td className="px-6 py-5 whitespace-nowrap">
                      <div className={getBadgeColor(anomaly.type)}>
                        {getTypeIcon(anomaly.type)}
                        <span className="font-medium">{getTypeLabel(anomaly.type)}</span>
                      </div>
                    </td>
                    <td className="px-6 py-5 text-sm text-gray-800">
                      <div className="leading-relaxed">
                        {anomaly.description}
                        {anomaly.packet_number && (
                          <div className="text-blue-600 font-medium text-xs mt-1.5 flex items-center gap-1">
                            <span className="inline-block w-1.5 h-1.5 rounded-full bg-blue-600"></span>
                            Packet #{anomaly.packet_number}
                          </div>
                        )}
                      </div>
                    </td>
                    <td className="px-6 py-5 whitespace-nowrap text-sm text-gray-600 font-mono">
                      <div className="truncate max-w-xs" title={anomaly.source_file}>
                        {anomaly.source_file}
                      </div>
                    </td>
                    <td className="px-6 py-5 whitespace-nowrap w-28">
                      <span className={`inline-flex items-center px-3 py-1.5 rounded-full text-xs font-bold uppercase tracking-wide ${
                        anomaly.severity === 'critical' 
                          ? 'bg-red-500 text-white shadow-red-200 shadow-lg' 
                          : anomaly.severity === 'high'
                          ? 'bg-orange-500 text-white shadow-orange-200 shadow-lg'
                          : anomaly.severity === 'medium'
                          ? 'bg-yellow-500 text-white shadow-yellow-200 shadow-lg'
                          : 'bg-green-500 text-white shadow-green-200 shadow-lg'
                      }`}>
                        {anomaly.severity?.charAt(0).toUpperCase() + anomaly.severity?.slice(1) || 'Unknown'}
                      </span>
                    </td>
                    <td className="px-6 py-5 whitespace-nowrap text-sm font-medium">
                      <div className="flex items-center gap-2">
                        <button
                          onClick={() => toggleRecommendations(anomaly)}
                          className="inline-flex items-center justify-center px-3 py-2 text-sm font-medium text-white bg-blue-600 rounded-md shadow-sm hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 transition-colors whitespace-nowrap"
                        >
                          {expandedAnomalyId === anomaly.id ? (
                            <>
                              <ChevronUp className="w-4 h-4 mr-1" />
                              Hide
                            </>
                          ) : (
                            <>
                              <Brain className="w-4 h-4 mr-1" />
                              Recommend
                            </>
                          )}
                        </button>
                        <button
                          onClick={() => handleGetDetails(anomaly)}
                          className="inline-flex items-center justify-center px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 transition-colors"
                        >
                          Details
                        </button>
                      </div>
                    </td>
                  </tr>

                  {/* Expandable Recommendations Row */}
                  {expandedAnomalyId === anomaly.id && (
                    <tr key={`${anomaly.timestamp}-${index}-expanded`} className="bg-blue-50/50">
                      <td colSpan={hasSelection ? 7 : 6} className="px-6 py-6">
                        <div className="bg-white rounded-lg border border-blue-200 p-6 shadow-sm">
                          <div className="flex items-center gap-2 mb-4">
                            <Brain className="w-5 h-5 text-blue-600" />
                            <h3 className="font-semibold text-gray-900">AI Troubleshooting Recommendations</h3>
                            {isStreaming && (
                              <Loader2 className="w-4 h-4 animate-spin text-blue-600 ml-2" />
                            )}
                          </div>
                          
                          {streamError ? (
                            <div className="bg-red-50 border border-red-200 rounded-md p-4 text-red-700">
                              <p className="font-medium">Error:</p>
                              <p className="text-sm mt-1">{streamError}</p>
                            </div>
                          ) : recommendations ? (
                            <div className="prose prose-sm max-w-none text-gray-800 whitespace-pre-wrap">
                              {recommendations}
                            </div>
                          ) : (
                            <div className="flex items-center justify-center py-8">
                              <div className="text-center">
                                <Loader2 className="w-8 h-8 animate-spin mx-auto mb-3 text-blue-600" />
                                <p className="text-gray-600">Connecting to AI...</p>
                                <p className="text-sm text-gray-500 mt-1">Generating recommendations</p>
                              </div>
                            </div>
                          )}
                        </div>
                      </td>
                    </tr>
                  )}
                </>
              ))
            )}
          </tbody>
        </table>
      </div>

      {/* Details Modal */}
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
