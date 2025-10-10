import { useState, useEffect, useRef } from 'react';
import { useSearchParams } from 'wouter';
import { Loader2, Brain, AlertCircle } from 'lucide-react';

export default function RecommendationsWindow() {
  const params = new URLSearchParams(window.location.search);
  const anomalyId = params.get('anomalyId');
  
  const [recommendations, setRecommendations] = useState<string>('');
  const [isStreaming, setIsStreaming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [anomaly, setAnomaly] = useState<any>(null);
  const eventSourceRef = useRef<EventSource | null>(null);

  useEffect(() => {
    if (!anomalyId) {
      setError('No anomaly ID provided');
      return;
    }

    // Fetch anomaly details
    fetch(`/api/anomalies/${anomalyId}`)
      .then(res => res.json())
      .then(data => setAnomaly(data))
      .catch(err => setError('Failed to load anomaly details'));

    // Start streaming recommendations
    fetchRecommendations();

    return () => {
      if (eventSourceRef.current) {
        eventSourceRef.current.close();
      }
    };
  }, [anomalyId]);

  const fetchRecommendations = () => {
    if (!anomalyId) return;

    setIsStreaming(true);
    setRecommendations('');
    setError(null);

    const sseUrl = `/api/recommendations/stream/${anomalyId}`;
    console.log('SSE: Connecting to', sseUrl);
    
    const eventSource = new EventSource(sseUrl);
    eventSourceRef.current = eventSource;

    eventSource.onopen = () => {
      console.log('SSE: Connection opened');
    };

    eventSource.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.content) {
          setRecommendations(prev => prev + data.content);
        }
      } catch (err) {
        console.error('SSE: Parse error:', err);
      }
    };

    eventSource.addEventListener('complete', () => {
      console.log('SSE: Stream complete');
      setIsStreaming(false);
      eventSource.close();
    });

    eventSource.addEventListener('error', (event: any) => {
      try {
        const data = JSON.parse(event.data);
        setError(data.message || 'Connection error');
      } catch {
        setError('Connection error');
      }
      setIsStreaming(false);
      eventSource.close();
    });

    eventSource.onerror = () => {
      console.error('SSE: Connection error');
      setError('Connection error. Please try again.');
      setIsStreaming(false);
      eventSource.close();
    };
  };

  const formatRecommendations = (content: string) => {
    if (!content) return null;

    // Define the headers to look for
    const headers = [
      '1. ROOT CAUSE ANALYSIS',
      '2. IMMEDIATE ACTIONS',
      '3. DETAILED INVESTIGATION',
      '4. RESOLUTION STEPS',
      '5. PREVENTION MEASURES'
    ];

    // Split content into sections
    const sections: { header: string; content: string }[] = [];
    let currentSection = { header: '', content: '' };

    const lines = content.split('\n');
    
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      
      // Check if line is a header
      const isHeader = headers.some(h => line.includes(h) || 
        line.includes(h.replace(/^\d+\.\s*/, '')) ||
        line.toUpperCase().includes(h.replace(/^\d+\.\s*/, '')));
      
      if (isHeader) {
        // Save previous section if it has content
        if (currentSection.header || currentSection.content) {
          sections.push({ ...currentSection });
        }
        // Start new section
        currentSection = { header: line, content: '' };
      } else if (line) {
        currentSection.content += (currentSection.content ? '\n' : '') + line;
      }
    }
    
    // Add last section
    if (currentSection.header || currentSection.content) {
      sections.push(currentSection);
    }

    // If no sections were found, treat entire content as single block
    if (sections.length === 0) {
      return <p className="text-sm text-gray-800 whitespace-pre-wrap leading-relaxed">{content}</p>;
    }

    return (
      <div className="space-y-4">
        {sections.map((section, idx) => (
          <div key={idx}>
            {section.header && (
              <h3 className="font-bold text-gray-900 text-base mb-2">{section.header}</h3>
            )}
            {section.content && (
              <p className="text-sm text-gray-800 whitespace-pre-wrap leading-relaxed ml-4">
                {section.content}
              </p>
            )}
          </div>
        ))}
      </div>
    );
  };

  return (
    <div className="min-h-screen bg-white">
      {/* Blue Header Bar */}
      <div className="bg-blue-500 px-6 py-4 flex items-center justify-between">
        <h1 className="text-xl font-semibold text-white">AI Troubleshooting Recommendations</h1>
        <button
          onClick={() => window.close()}
          className="text-white hover:text-gray-200 transition-colors text-2xl font-light leading-none"
          aria-label="Close"
        >
          ×
        </button>
      </div>

      <div className="max-w-4xl mx-auto p-8">
        {/* Anomaly Info */}
        <div className="bg-white rounded-lg shadow-lg p-6 mb-6 border border-gray-200">
          
          {anomaly && (
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
              <div>
                <span className="font-medium text-gray-700">Type:</span>
                <p className="text-gray-900">{anomaly.type?.replace(/_/g, ' ')}</p>
              </div>
              <div>
                <span className="font-medium text-gray-700">Severity:</span>
                <p className="text-gray-900 capitalize">{anomaly.severity}</p>
              </div>
              <div>
                <span className="font-medium text-gray-700">Source:</span>
                <p className="text-gray-900 text-xs truncate">{anomaly.source_file}</p>
              </div>
              <div>
                <span className="font-medium text-gray-700">Timestamp:</span>
                <p className="text-gray-900 text-xs">{new Date(anomaly.timestamp).toLocaleString()}</p>
              </div>
              <div className="col-span-2 md:col-span-4">
                <span className="font-medium text-gray-700">Description:</span>
                <p className="text-gray-900 mt-1">{anomaly.description}</p>
              </div>
            </div>
          )}
        </div>

        {/* Recommendations */}
        <div className="bg-white rounded-lg shadow-lg p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-semibold text-gray-900">Recommendations</h2>
            {isStreaming && (
              <div className="flex items-center gap-2 text-sm text-gray-600">
                <Loader2 className="h-4 w-4 animate-spin" />
                Streaming...
              </div>
            )}
          </div>

          {error ? (
            <div className="flex items-center gap-2 p-4 border border-red-200 rounded-lg bg-red-50">
              <AlertCircle className="h-5 w-5 text-red-600" />
              <div>
                <p className="font-medium text-red-800">Error</p>
                <p className="text-sm text-red-600 mt-1">{error}</p>
              </div>
            </div>
          ) : recommendations ? (
            <div className="relative">
              <div className="w-full min-h-[200px] max-h-[800px] p-4 border border-gray-200 rounded-lg font-sans overflow-y-auto bg-white">
                {formatRecommendations(recommendations)}
              </div>
              {isStreaming && (
                <span className="absolute bottom-4 right-4 inline-block w-2 h-4 bg-blue-600 animate-pulse" />
              )}
            </div>
          ) : (
            <div className="flex items-center justify-center py-12">
              <div className="text-center">
                <Loader2 className="h-8 w-8 animate-spin mx-auto mb-3 text-blue-600" />
                <p className="text-gray-600">Connecting to AI...</p>
                <p className="text-sm text-gray-500 mt-1">Generating recommendations</p>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
