import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Loader2, AlertCircle, TrendingUp, TrendingDown } from 'lucide-react';

export default function DetailsWindow() {
  const params = new URLSearchParams(window.location.search);
  const anomalyId = params.get('anomalyId');
  
  const { data: explanation, isLoading, error } = useQuery({
    queryKey: [`/api/anomalies/${anomalyId}/explanation`],
    enabled: !!anomalyId,
  });

  const { data: anomaly } = useQuery({
    queryKey: [`/api/anomalies/${anomalyId}`],
    enabled: !!anomalyId,
  });

  if (!anomalyId) {
    return (
      <div className="min-h-screen bg-gray-50 p-8 flex items-center justify-center">
        <div className="text-red-600">No anomaly ID provided</div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-white">
      {/* Blue Header Bar */}
      <div className="bg-blue-500 px-6 py-4 flex items-center justify-between">
        <h1 className="text-xl font-semibold text-white">Anomaly Details & AI Analysis</h1>
        <button
          onClick={() => window.close()}
          className="text-white hover:text-gray-200 transition-colors text-2xl font-light leading-none"
          aria-label="Close"
        >
          ×
        </button>
      </div>

      <div className="max-w-3xl mx-auto p-6">
        {/* Anomaly Info */}
        <div className="bg-white rounded-lg shadow-lg p-6 mb-6 border border-gray-200">
          
          {anomaly && (
            <div className="grid grid-cols-2 gap-4 text-sm">
              <div>
                <span className="font-medium text-gray-700">Type:</span>
                <p className="text-gray-900 capitalize">{anomaly.type?.replace(/_/g, ' ')}</p>
              </div>
              <div>
                <span className="font-medium text-gray-700">Severity:</span>
                <p className="text-gray-900 capitalize">{anomaly.severity}</p>
              </div>
              <div className="col-span-2">
                <span className="font-medium text-gray-700">Description:</span>
                <p className="text-gray-900 mt-1">{anomaly.description}</p>
              </div>
              <div>
                <span className="font-medium text-gray-700">Source:</span>
                <p className="text-gray-900 text-xs">{anomaly.source_file}</p>
              </div>
              <div>
                <span className="font-medium text-gray-700">Timestamp:</span>
                <p className="text-gray-900 text-xs">{new Date(anomaly.timestamp).toLocaleString()}</p>
              </div>
            </div>
          )}
          
          {/* Packet Context Section */}
          {anomaly && anomaly.packet_context && (
            <div className="mt-6 pt-6 border-t border-gray-200">
              <h3 className="font-semibold text-gray-900 mb-3">Packet Context</h3>
              <div className="bg-gray-50 rounded-lg p-4 border border-gray-200">
                <pre className="text-xs text-gray-700 whitespace-pre-wrap font-mono overflow-x-auto">
                  {anomaly.packet_context}
                </pre>
              </div>
              <p className="text-xs text-gray-500 mt-2">
                Context shows anomaly packet and surrounding network traffic (±2 packets)
              </p>
            </div>
          )}
        </div>

        {/* Explanation Content */}
        {isLoading ? (
          <div className="bg-white rounded-lg shadow-lg p-12">
            <div className="flex items-center justify-center">
              <div className="text-center">
                <Loader2 className="h-8 w-8 animate-spin mx-auto mb-3 text-blue-600" />
                <p className="text-gray-600">Loading analysis...</p>
              </div>
            </div>
          </div>
        ) : error ? (
          <div className="bg-white rounded-lg shadow-lg p-6">
            <div className="flex items-center gap-2 p-4 border border-red-200 rounded-lg bg-red-50">
              <AlertCircle className="h-5 w-5 text-red-600" />
              <div>
                <p className="font-medium text-red-800">Error loading analysis</p>
                <p className="text-sm text-red-600 mt-1">Failed to load anomaly explanation</p>
              </div>
            </div>
          </div>
        ) : explanation ? (
          <div className="space-y-6">
            {/* Overall Confidence */}
            <div className="bg-white rounded-lg shadow-lg p-6">
              <h2 className="text-lg font-semibold text-gray-900 mb-4">Overall Confidence</h2>
              <div className="flex items-center gap-4">
                <div className="flex-1">
                  <div className="h-4 bg-gray-200 rounded-full overflow-hidden">
                    <div
                      className="h-full bg-blue-600 transition-all"
                      style={{ width: `${(explanation.overall_confidence || 0) * 100}%` }}
                    />
                  </div>
                </div>
                <span className="text-2xl font-bold text-gray-900">
                  {((explanation.overall_confidence || 0) * 100).toFixed(1)}%
                </span>
              </div>
              <p className="text-sm text-gray-600 mt-2">
                {explanation.model_agreement || 0} out of 4 ML models detected this anomaly
              </p>
            </div>

            {/* Human Explanation */}
            <div className="bg-white rounded-lg shadow-lg p-6">
              <h2 className="text-lg font-semibold text-gray-900 mb-4">AI Analysis</h2>
              <div className="prose prose-sm max-w-none text-gray-700">
                <pre className="whitespace-pre-wrap font-sans">{explanation.human_explanation}</pre>
              </div>
            </div>

            {/* Model Explanations */}
            <div className="bg-white rounded-lg shadow-lg p-6">
              <h2 className="text-lg font-semibold text-gray-900 mb-4">ML Model Analysis</h2>
              <div className="space-y-4">
                {explanation.model_explanations && Object.entries(explanation.model_explanations).map(([model, data]: [string, any]) => (
                  <div key={model} className="border rounded-lg p-4">
                    <div className="flex items-center justify-between mb-3">
                      <h3 className="font-medium text-gray-900 capitalize">
                        {model.replace(/_/g, ' ')}
                      </h3>
                      <div className="flex items-center gap-2">
                        <span className={`px-2 py-1 rounded text-xs font-medium ${
                          data.decision === 'ANOMALY' 
                            ? 'bg-red-100 text-red-800' 
                            : 'bg-green-100 text-green-800'
                        }`}>
                          {data.decision}
                        </span>
                        <span className="text-sm font-semibold text-gray-700">
                          {(data.confidence * 100).toFixed(1)}%
                        </span>
                      </div>
                    </div>

                    {data.top_positive_features && data.top_positive_features.length > 0 && (
                      <div className="mt-3">
                        <p className="text-xs font-medium text-gray-600 mb-2 flex items-center gap-1">
                          <TrendingUp className="h-3 w-3" />
                          Top Contributing Factors
                        </p>
                        <div className="space-y-1">
                          {data.top_positive_features.slice(0, 3).map((feature: any, idx: number) => (
                            <div key={idx} className="flex items-center justify-between text-xs">
                              <span className="text-gray-700">{feature.feature}</span>
                              <span className="font-medium text-blue-600">
                                {(feature.impact * 100).toFixed(1)}%
                              </span>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          </div>
        ) : null}
      </div>
    </div>
  );
}
