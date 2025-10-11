import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { Database, Upload, Trash2, Search, FileText, CheckCircle, XCircle, File } from "lucide-react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";

interface RAGStats {
  total_documents: number;
  anomaly_cases: number;
  general_documents: number;
  stored_files: number;
  collection_name: string;
  persist_directory: string;
}

interface RAGDocument {
  anomaly_id: string;
  distance?: number;
  metadata: {
    anomaly_id: string;
    anomaly_type: string;
    severity: string;
    error_log: string;
    recommendation: string;
    resolution_notes: string;
    indexed_at: string;
  };
  document: string;
}

interface SearchResult {
  success: boolean;
  results: RAGDocument[];
  count: number;
}

export default function RAGManagement() {
  const queryClient = useQueryClient();
  const [searchQuery, setSearchQuery] = useState("");
  const [uploadForm, setUploadForm] = useState({
    anomaly_id: "",
    anomaly_type: "fronthaul",
    severity: "medium",
    error_log: "",
    recommendation: "",
    resolution_notes: ""
  });
  const [uploadSuccess, setUploadSuccess] = useState(false);
  const [uploadError, setUploadError] = useState("");
  const [searchError, setSearchError] = useState("");
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [fileUploadSuccess, setFileUploadSuccess] = useState(false);
  const [fileUploadError, setFileUploadError] = useState("");

  const { data: stats } = useQuery<RAGStats>({
    queryKey: ["/api/rag/stats"],
    refetchInterval: 10000,
  });

  const { data: searchResults, refetch: searchDocuments } = useQuery<SearchResult>({
    queryKey: ["/api/rag/search", searchQuery],
    enabled: false,
  });

  const uploadMutation = useMutation({
    mutationFn: async (data: typeof uploadForm) => {
      const response = await fetch("/api/rag/add-document", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(data),
      });
      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.error || "Upload failed");
      }
      return response.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["/api/rag/stats"] });
      setUploadSuccess(true);
      setUploadError("");
      setUploadForm({
        anomaly_id: "",
        anomaly_type: "fronthaul",
        severity: "medium",
        error_log: "",
        recommendation: "",
        resolution_notes: ""
      });
      setTimeout(() => setUploadSuccess(false), 3000);
    },
    onError: (error: Error) => {
      setUploadError(error.message);
      setUploadSuccess(false);
      setTimeout(() => setUploadError(""), 5000);
    },
  });

  const fileUploadMutation = useMutation({
    mutationFn: async (file: File) => {
      const formData = new FormData();
      formData.append('file', file);

      const response = await fetch("/api/rag/upload-file", {
        method: "POST",
        body: formData,
      });

      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.error || "File upload failed");
      }
      return response.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["/api/rag/stats"] });
      setFileUploadSuccess(true);
      setFileUploadError("");
      setSelectedFile(null);
      setTimeout(() => setFileUploadSuccess(false), 3000);
    },
    onError: (error: Error) => {
      setFileUploadError(error.message);
      setFileUploadSuccess(false);
      setTimeout(() => setFileUploadError(""), 5000);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: async (anomalyId: string) => {
      const response = await fetch(`/api/rag/delete-document/${anomalyId}`, {
        method: "DELETE",
      });
      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.error || "Delete failed");
      }
      return response.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["/api/rag/stats"] });
      if (searchQuery) {
        searchDocuments();
      }
    },
    onError: (error: Error) => {
      setSearchError(error.message);
      setTimeout(() => setSearchError(""), 5000);
    },
  });

  const handleSearch = async () => {
    if (!searchQuery.trim()) return;
    
    try {
      setSearchError("");
      const response = await fetch("/api/rag/search", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          query_text: searchQuery,
          n_results: 10
        }),
      });
      
      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.error || "Search failed");
      }
      
      const data = await response.json();
      queryClient.setQueryData(["/api/rag/search", searchQuery], data);
    } catch (error: any) {
      setSearchError(error.message);
      setTimeout(() => setSearchError(""), 5000);
    }
  };

  const handleUpload = () => {
    uploadMutation.mutate(uploadForm);
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files[0]) {
      setSelectedFile(e.target.files[0]);
    }
  };

  const handleFileUpload = () => {
    if (selectedFile) {
      fileUploadMutation.mutate(selectedFile);
    }
  };

  const handleDelete = (anomalyId: string) => {
    if (confirm(`Are you sure you want to delete document ${anomalyId}?`)) {
      deleteMutation.mutate(anomalyId);
    }
  };

  return (
    <div className="p-8 bg-gray-50 min-h-screen">
      <div className="mb-8">
        <h1 className="text-2xl font-bold text-gray-900 mb-2">RAG Knowledge Base</h1>
        <p className="text-gray-600">Manage resolved anomaly cases for AI-enhanced recommendations</p>
      </div>

      {/* Stats Card */}
      <Card className="mb-8">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Database className="h-5 w-5" />
            Knowledge Base Statistics
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-6 mb-6">
            <div>
              <p className="text-sm text-gray-600 mb-1">Total Chunks (Vector DB)</p>
              <p className="text-3xl font-bold text-blue-600">{stats?.total_documents || 0}</p>
            </div>
            <div>
              <p className="text-sm text-gray-600 mb-1">Anomaly Cases</p>
              <p className="text-3xl font-bold text-green-600">{stats?.anomaly_cases || 0}</p>
            </div>
            <div>
              <p className="text-sm text-gray-600 mb-1">General Documents</p>
              <p className="text-3xl font-bold text-purple-600">{stats?.general_documents || 0}</p>
            </div>
            <div>
              <p className="text-sm text-gray-600 mb-1">Original Files Stored</p>
              <p className="text-3xl font-bold text-orange-600">{stats?.stored_files || 0}</p>
            </div>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 pt-4 border-t border-gray-200">
            <div>
              <p className="text-sm text-gray-600 mb-1">Collection Name</p>
              <p className="text-lg font-medium text-gray-900">{stats?.collection_name || "N/A"}</p>
            </div>
            <div>
              <p className="text-sm text-gray-600 mb-1">Storage Location</p>
              <p className="text-sm font-mono text-gray-700">{stats?.persist_directory || "N/A"}</p>
            </div>
          </div>
        </CardContent>
      </Card>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
        {/* Upload Form */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Upload className="h-5 w-5" />
              Add Document to Knowledge Base
            </CardTitle>
            <CardDescription>
              Upload a resolved anomaly case to enhance AI recommendations
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {uploadSuccess && (
              <div className="flex items-center gap-2 p-3 bg-green-50 border border-green-200 rounded-lg text-green-700">
                <CheckCircle className="h-5 w-5" />
                Document uploaded successfully!
              </div>
            )}
            
            {uploadError && (
              <div className="flex items-center gap-2 p-3 bg-red-50 border border-red-200 rounded-lg text-red-700">
                <XCircle className="h-5 w-5" />
                {uploadError}
              </div>
            )}
            
            <div>
              <Label htmlFor="anomaly_id">Anomaly ID *</Label>
              <Input
                id="anomaly_id"
                value={uploadForm.anomaly_id}
                onChange={(e) => setUploadForm({ ...uploadForm, anomaly_id: e.target.value })}
                placeholder="e.g., ANOM-2025-001"
              />
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <Label htmlFor="anomaly_type">Anomaly Type *</Label>
                <select
                  id="anomaly_type"
                  value={uploadForm.anomaly_type}
                  onChange={(e) => setUploadForm({ ...uploadForm, anomaly_type: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                >
                  <option value="fronthaul">Fronthaul</option>
                  <option value="ue_event">UE Event</option>
                  <option value="mac_address">MAC Address</option>
                  <option value="protocol">Protocol</option>
                </select>
              </div>

              <div>
                <Label htmlFor="severity">Severity *</Label>
                <select
                  id="severity"
                  value={uploadForm.severity}
                  onChange={(e) => setUploadForm({ ...uploadForm, severity: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                >
                  <option value="low">Low</option>
                  <option value="medium">Medium</option>
                  <option value="high">High</option>
                  <option value="critical">Critical</option>
                </select>
              </div>
            </div>

            <div>
              <Label htmlFor="error_log">Error Log / Technical Details *</Label>
              <Textarea
                id="error_log"
                value={uploadForm.error_log}
                onChange={(e) => setUploadForm({ ...uploadForm, error_log: e.target.value })}
                placeholder="Describe the technical details and error logs..."
                rows={3}
              />
            </div>

            <div>
              <Label htmlFor="recommendation">Recommendation *</Label>
              <Textarea
                id="recommendation"
                value={uploadForm.recommendation}
                onChange={(e) => setUploadForm({ ...uploadForm, recommendation: e.target.value })}
                placeholder="What actions were recommended?"
                rows={3}
              />
            </div>

            <div>
              <Label htmlFor="resolution_notes">Resolution Notes</Label>
              <Textarea
                id="resolution_notes"
                value={uploadForm.resolution_notes}
                onChange={(e) => setUploadForm({ ...uploadForm, resolution_notes: e.target.value })}
                placeholder="How was this issue resolved?"
                rows={2}
              />
            </div>

            <Button 
              onClick={handleUpload}
              disabled={!uploadForm.anomaly_id || !uploadForm.error_log || !uploadForm.recommendation || uploadMutation.isPending}
              className="w-full"
            >
              {uploadMutation.isPending ? "Uploading..." : "Upload to Knowledge Base"}
            </Button>
          </CardContent>
        </Card>

        {/* Search and Display */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Search className="h-5 w-5" />
              Search Knowledge Base
            </CardTitle>
            <CardDescription>
              Find similar cases using semantic search
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex gap-2">
              <Input
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search for similar cases..."
                onKeyPress={(e) => e.key === 'Enter' && handleSearch()}
              />
              <Button onClick={handleSearch} disabled={!searchQuery.trim()}>
                Search
              </Button>
            </div>

            {searchError && (
              <div className="flex items-center gap-2 p-3 bg-red-50 border border-red-200 rounded-lg text-red-700">
                <XCircle className="h-5 w-5" />
                {searchError}
              </div>
            )}

            {searchResults && searchResults.results && searchResults.results.length > 0 && (
              <div className="space-y-4 max-h-[600px] overflow-y-auto">
                <p className="text-sm text-gray-600">Found {searchResults.count} similar cases</p>
                
                {searchResults.results.map((doc) => (
                  <div key={doc.metadata.anomaly_id} className="border border-gray-200 rounded-lg p-4 bg-white">
                    <div className="flex items-start justify-between mb-3">
                      <div className="flex items-center gap-2">
                        <FileText className="h-5 w-5 text-blue-600" />
                        <div>
                          <h3 className="font-semibold text-gray-900">{doc.metadata.anomaly_id}</h3>
                          <div className="flex gap-2 mt-1">
                            <span className="text-xs px-2 py-0.5 bg-blue-100 text-blue-700 rounded-full">
                              {doc.metadata.anomaly_type}
                            </span>
                            <span className={`text-xs px-2 py-0.5 rounded-full ${
                              doc.metadata.severity === 'critical' ? 'bg-red-100 text-red-700' :
                              doc.metadata.severity === 'high' ? 'bg-orange-100 text-orange-700' :
                              doc.metadata.severity === 'medium' ? 'bg-yellow-100 text-yellow-700' :
                              'bg-green-100 text-green-700'
                            }`}>
                              {doc.metadata.severity}
                            </span>
                          </div>
                        </div>
                      </div>
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => handleDelete(doc.metadata.anomaly_id)}
                        className="text-red-600 hover:text-red-700 hover:bg-red-50"
                      >
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </div>
                    
                    {doc.distance !== undefined && (
                      <p className="text-xs text-gray-500 mb-2">
                        Similarity: {((1 - doc.distance) * 100).toFixed(1)}%
                      </p>
                    )}
                    
                    <div className="space-y-2 text-sm">
                      <div>
                        <p className="font-medium text-gray-700">Error Log:</p>
                        <p className="text-gray-600">{doc.metadata.error_log}</p>
                      </div>
                      <div>
                        <p className="font-medium text-gray-700">Recommendation:</p>
                        <p className="text-gray-600">{doc.metadata.recommendation}</p>
                      </div>
                      {doc.metadata.resolution_notes && (
                        <div>
                          <p className="font-medium text-gray-700">Resolution:</p>
                          <p className="text-gray-600">{doc.metadata.resolution_notes}</p>
                        </div>
                      )}
                      <p className="text-xs text-gray-400">
                        Indexed: {new Date(doc.metadata.indexed_at).toLocaleString()}
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            )}

            {searchResults && searchResults.results && searchResults.results.length === 0 && (
              <div className="flex flex-col items-center justify-center py-12 text-gray-500">
                <XCircle className="h-12 w-12 mb-3" />
                <p>No similar cases found</p>
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* File Upload Card */}
      <Card className="mt-8">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <File className="h-5 w-5" />
            Upload Document Files
          </CardTitle>
          <CardDescription>
            Upload PDF, TXT, or MD files to add general documentation to the knowledge base
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {fileUploadSuccess && (
            <div className="flex items-center gap-2 p-3 bg-green-50 border border-green-200 rounded-lg text-green-700">
              <CheckCircle className="h-5 w-5" />
              File uploaded successfully!
            </div>
          )}
          
          {fileUploadError && (
            <div className="flex items-center gap-2 p-3 bg-red-50 border border-red-200 rounded-lg text-red-700">
              <XCircle className="h-5 w-5" />
              {fileUploadError}
            </div>
          )}

          <div className="flex items-center gap-4">
            <div className="flex-1">
              <Input
                type="file"
                accept=".pdf,.txt,.md"
                onChange={handleFileChange}
                className="cursor-pointer"
              />
              {selectedFile && (
                <p className="text-sm text-gray-600 mt-2">
                  Selected: {selectedFile.name} ({(selectedFile.size / 1024).toFixed(2)} KB)
                </p>
              )}
            </div>
            <Button 
              onClick={handleFileUpload}
              disabled={!selectedFile || fileUploadMutation.isPending}
              className="whitespace-nowrap"
            >
              {fileUploadMutation.isPending ? "Uploading..." : "Upload File"}
            </Button>
          </div>

          <p className="text-xs text-gray-500">
            Supported formats: PDF, TXT, MD • Max size: 10MB
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
