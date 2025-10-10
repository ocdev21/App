import { useState, useEffect } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Copy, Download, X } from "lucide-react";
import { wsClient } from "@/lib/websocket";
import { useToast } from "@/hooks/use-toast";

interface RecommendationsModalProps {
  isOpen: boolean;
  onClose: () => void;
  anomaly: {
    id: string;
    description: string;
  } | null;
}

export default function RecommendationsModal({
  isOpen,
  onClose,
  anomaly,
}: RecommendationsModalProps) {
  const [streamingContent, setStreamingContent] = useState("");
  const [isStreaming, setIsStreaming] = useState(false);
  const { toast } = useToast();

  useEffect(() => {
    if (isOpen && anomaly) {
      setStreamingContent("");
      setIsStreaming(true);
      
      // Connect to WebSocket if not already connected
      if (!wsClient.isConnected()) {
        wsClient.connect().then(() => {
          requestRecommendations();
        }).catch((error) => {
          console.error('Failed to connect to WebSocket:', error);
          setIsStreaming(false);
          setStreamingContent("Error: Unable to connect to recommendation service.");
        });
      } else {
        requestRecommendations();
      }

      // Set up message handler
      wsClient.onMessage((data) => {
        if (data.type === 'recommendation_chunk') {
          setStreamingContent(prev => prev + data.data);
        } else if (data.type === 'recommendation_complete') {
          setIsStreaming(false);
        } else if (data.type === 'error') {
          setIsStreaming(false);
          setStreamingContent(prev => prev + "\n\nError: " + data.data);
        }
      });
    }
  }, [isOpen, anomaly]);

  const requestRecommendations = () => {
    if (anomaly) {
      wsClient.send({
        type: 'get_recommendations',
        anomalyId: anomaly.id,
        description: anomaly.description,
      });
    }
  };

  const copyToClipboard = async () => {
    try {
      await navigator.clipboard.writeText(streamingContent);
      toast({
        title: "Copied to clipboard",
        description: "Recommendations have been copied to your clipboard.",
      });
    } catch (error) {
      toast({
        title: "Copy failed",
        description: "Unable to copy to clipboard.",
        variant: "destructive",
      });
    }
  };

  const exportRecommendations = () => {
    const blob = new Blob([streamingContent], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `anomaly-recommendations-${anomaly?.id}.txt`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
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
      return <p className="text-sm text-slate-700 whitespace-pre-wrap leading-relaxed">{content}</p>;
    }

    return (
      <div className="space-y-4">
        {sections.map((section, idx) => (
          <div key={idx}>
            {section.header && (
              <h3 className="font-bold text-slate-900 mb-2">{section.header}</h3>
            )}
            {section.content && (
              <p className="text-sm text-slate-700 whitespace-pre-wrap leading-relaxed ml-4">
                {section.content}
              </p>
            )}
          </div>
        ))}
      </div>
    );
  };

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="max-w-2xl max-h-[80vh] overflow-hidden">
        <DialogHeader>
          <DialogTitle className="flex items-center justify-between">
            AI Recommendations
            <Button
              variant="ghost"
              size="sm"
              onClick={onClose}
              className="h-8 w-8 p-0"
            >
              <X className="h-4 w-4" />
            </Button>
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          <div>
            <h4 className="text-sm font-medium text-slate-700 mb-2">
              Anomaly Description:
            </h4>
            <p className="text-sm text-slate-600 bg-slate-50 p-3 rounded-lg">
              {anomaly?.description || "Loading anomaly details..."}
            </p>
          </div>

          <div>
            <div className="flex items-center justify-between mb-2">
              <h4 className="text-sm font-medium text-slate-700">
                TSLAM Analysis & Recommendations:
              </h4>
              {isStreaming && (
                <div className="flex items-center text-primary text-xs">
                  <div className="animate-pulse w-2 h-2 bg-primary rounded-full mr-2"></div>
                  Analyzing...
                </div>
              )}
            </div>
            <div className="bg-slate-50 p-4 rounded-lg min-h-[200px] max-h-[800px] overflow-y-auto border border-gray-200 streaming-content">
              {streamingContent ? (
                formatRecommendations(streamingContent)
              ) : (
                <div className="text-slate-500 text-sm animate-pulse">
                  Connecting to TSLAM model...
                </div>
              )}
            </div>
          </div>

          <div className="flex justify-end space-x-3">
            <Button
              variant="outline"
              onClick={copyToClipboard}
              disabled={!streamingContent}
            >
              <Copy className="w-4 h-4 mr-2" />
              Copy
            </Button>
            <Button
              onClick={exportRecommendations}
              disabled={!streamingContent}
              style={{ backgroundColor: 'hsl(var(--primary-blue))', color: 'white' }}
            >
              <Download className="w-4 h-4 mr-2" />
              Export
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
