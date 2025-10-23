import { useState, useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { Search } from "lucide-react";
import AnomalyTable from "../components/anomaly-table";
import { RecommendationsPopup } from "../components/RecommendationsPopup";
import { ExplainableAIModal } from "../components/ExplainableAIModal";
import type { Anomaly } from "@shared/schema";

type SortField = 'timestamp' | 'type' | 'severity' | 'description' | 'source_file';
type SortOrder = 'asc' | 'desc';

export default function Anomalies() {
  const [searchTerm, setSearchTerm] = useState("");
  const [sortField, setSortField] = useState<SortField>('timestamp');
  const [sortOrder, setSortOrder] = useState<SortOrder>('desc');
  const [currentPage, setCurrentPage] = useState(1);
  const [itemsPerPage, setItemsPerPage] = useState(10);
  const [selectedAnomaly, setSelectedAnomaly] = useState<Anomaly | null>(null);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [selectedAnomalyForDetails, setSelectedAnomalyForDetails] = useState<Anomaly | null>(null);
  const [isDetailsModalOpen, setIsDetailsModalOpen] = useState(false);
  
  // Filter input states (before submit)
  const [inputDateFrom, setInputDateFrom] = useState("");
  const [inputDateTo, setInputDateTo] = useState("");
  const [inputDescription, setInputDescription] = useState("");
  const [inputSeverity, setInputSeverity] = useState("");
  
  // Applied filter states (after submit)
  const [filterDateFrom, setFilterDateFrom] = useState("");
  const [filterDateTo, setFilterDateTo] = useState("");
  const [filterDescription, setFilterDescription] = useState("");
  const [filterSeverity, setFilterSeverity] = useState("");

  const { data: anomalies = [], isLoading } = useQuery<Anomaly[]>({
    queryKey: ["/api/anomalies?limit=10000"],
    refetchInterval: 10000,
  });

  // Filter and sort anomalies
  const filteredAndSortedAnomalies = useMemo(() => {
    let filtered = anomalies.filter((anomaly) => {
      // Search term filter (searches across all fields)
      if (searchTerm) {
        const search = searchTerm.toLowerCase();
        const matchesSearch = (
          anomaly.description?.toLowerCase().includes(search) ||
          anomaly.type?.toLowerCase().includes(search) ||
          anomaly.source_file?.toLowerCase().includes(search) ||
          anomaly.severity?.toLowerCase().includes(search)
        );
        if (!matchesSearch) return false;
      }
      
      // Date from filter
      if (filterDateFrom) {
        const anomalyDate = new Date(anomaly.timestamp);
        const fromDate = new Date(filterDateFrom);
        fromDate.setHours(0, 0, 0, 0);
        if (anomalyDate < fromDate) return false;
      }
      
      // Date to filter
      if (filterDateTo) {
        const anomalyDate = new Date(anomaly.timestamp);
        const toDate = new Date(filterDateTo);
        toDate.setHours(23, 59, 59, 999);
        if (anomalyDate > toDate) return false;
      }
      
      // Description filter
      if (filterDescription) {
        const descSearch = filterDescription.toLowerCase();
        if (!anomaly.description?.toLowerCase().includes(descSearch)) return false;
      }
      
      // Severity filter
      if (filterSeverity) {
        if (anomaly.severity?.toLowerCase() !== filterSeverity.toLowerCase()) return false;
      }
      
      return true;
    });

    // Sort
    filtered.sort((a, b) => {
      let aVal: any = a[sortField];
      let bVal: any = b[sortField];

      if (sortField === 'timestamp') {
        aVal = new Date(aVal).getTime();
        bVal = new Date(bVal).getTime();
      }

      if (aVal < bVal) return sortOrder === 'asc' ? -1 : 1;
      if (aVal > bVal) return sortOrder === 'asc' ? 1 : -1;
      return 0;
    });

    return filtered;
  }, [anomalies, searchTerm, filterDateFrom, filterDateTo, filterDescription, filterSeverity, sortField, sortOrder]);

  // Pagination
  const totalPages = Math.ceil(filteredAndSortedAnomalies.length / itemsPerPage);
  const paginatedAnomalies = filteredAndSortedAnomalies.slice(
    (currentPage - 1) * itemsPerPage,
    currentPage * itemsPerPage
  );

  const handleSort = (field: SortField) => {
    if (sortField === field) {
      setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortOrder('asc');
    }
  };

  const startEntry = (currentPage - 1) * itemsPerPage + 1;
  const endEntry = Math.min(currentPage * itemsPerPage, filteredAndSortedAnomalies.length);

  const handleGetRecommendations = (anomaly: Anomaly) => {
    console.log('Opening recommendations window for anomaly:', anomaly.id);
    // Open recommendations in a new window
    const width = 900;
    const height = 700;
    const left = (window.screen.width - width) / 2;
    const top = (window.screen.height - height) / 2;
    
    window.open(
      `/recommendations-window?anomalyId=${anomaly.id}`,
      '_blank',
      `width=${width},height=${height},left=${left},top=${top},toolbar=no,location=no,menubar=no,status=no,resizable=yes,scrollbars=yes`
    );
  };

  const handleGetDetails = (anomaly: Anomaly) => {
    console.log('Opening details window for anomaly:', anomaly.id);
    // Open details in a smaller window
    const width = 700;
    const height = 600;
    const left = (window.screen.width - width) / 2;
    const top = (window.screen.height - height) / 2;
    
    window.open(
      `/details-window?anomalyId=${anomaly.id}`,
      '_blank',
      `width=${width},height=${height},left=${left},top=${top},toolbar=no,location=no,menubar=no,status=no,resizable=yes,scrollbars=yes`
    );
  };

  const handleSubmitFilters = () => {
    setFilterDateFrom(inputDateFrom);
    setFilterDateTo(inputDateTo);
    setFilterDescription(inputDescription);
    setFilterSeverity(inputSeverity);
    setCurrentPage(1);
  };

  const handleClearFilters = () => {
    setInputDateFrom("");
    setInputDateTo("");
    setInputDescription("");
    setInputSeverity("");
    setFilterDateFrom("");
    setFilterDateTo("");
    setFilterDescription("");
    setFilterSeverity("");
    setCurrentPage(1);
  };

  return (
    <div className="p-8 bg-gray-50 min-h-screen">
      {/* Page Header */}
      <div className="mb-8">
        <h1 className="text-2xl font-bold text-gray-900 mb-2">Anomalies</h1>
        <p className="text-gray-600">Detected network anomalies and recommendations</p>
      </div>

      {/* Filters Section */}
      <div className="mb-6 bg-white rounded-lg shadow p-4 border border-gray-300">
        <h3 className="text-sm font-semibold text-gray-700 mb-3">Filters</h3>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {/* Date From */}
          <div>
            <label className="block text-xs text-gray-600 mb-1">Date From</label>
            <input
              type="date"
              value={inputDateFrom}
              onChange={(e) => setInputDateFrom(e.target.value)}
              className="border border-gray-300 rounded px-3 py-1.5 bg-white text-sm max-w-[180px]"
            />
          </div>

          {/* Date To */}
          <div>
            <label className="block text-xs text-gray-600 mb-1">Date To</label>
            <input
              type="date"
              value={inputDateTo}
              onChange={(e) => setInputDateTo(e.target.value)}
              className="border border-gray-300 rounded px-3 py-1.5 bg-white text-sm max-w-[180px]"
            />
          </div>

          {/* Description Search */}
          <div>
            <label className="block text-xs text-gray-600 mb-1">Description</label>
            <input
              type="text"
              value={inputDescription}
              onChange={(e) => setInputDescription(e.target.value)}
              placeholder="Search description..."
              className="w-full border border-gray-300 rounded px-3 py-1.5 bg-white text-sm"
            />
          </div>

          {/* Severity Filter */}
          <div>
            <label className="block text-xs text-gray-600 mb-1">Severity</label>
            <select
              value={inputSeverity}
              onChange={(e) => setInputSeverity(e.target.value)}
              className="w-full border border-gray-300 rounded px-3 py-1.5 bg-white text-sm"
            >
              <option value="">All Severities</option>
              <option value="critical">Critical</option>
              <option value="high">High</option>
              <option value="medium">Medium</option>
              <option value="low">Low</option>
            </select>
          </div>
        </div>

        {/* Submit and Clear Buttons */}
        <div className="mt-3 flex justify-end gap-3">
          <button
            onClick={handleClearFilters}
            className="px-4 py-2 text-sm text-gray-700 bg-white border border-gray-300 rounded-full hover:bg-gray-50 font-medium"
          >
            Clear Filters
          </button>
          <button
            onClick={handleSubmitFilters}
            className="px-4 py-2 text-sm text-white bg-blue-600 rounded-full hover:bg-blue-700 font-medium"
          >
            Submit
          </button>
        </div>
      </div>

      {/* Controls Bar */}
      <div className="mb-6 flex items-center justify-between">
        {/* Display selector */}
        <div className="flex items-center gap-2 text-sm text-gray-700">
          <span>Display</span>
          <select
            value={itemsPerPage}
            onChange={(e) => {
              setItemsPerPage(Number(e.target.value));
              setCurrentPage(1);
            }}
            className="border border-gray-300 rounded px-2 py-1 bg-white"
          >
            <option value="10">10</option>
            <option value="25">25</option>
            <option value="50">50</option>
            <option value="100">100</option>
          </select>
          <span>results</span>
        </div>

        {/* Search */}
        <div className="flex items-center gap-2">
          <label className="text-sm text-gray-700">Search:</label>
          <input
            type="text"
            value={searchTerm}
            onChange={(e) => {
              setSearchTerm(e.target.value);
              setCurrentPage(1);
            }}
            placeholder="Search all fields..."
            className="border border-gray-300 rounded px-3 py-1 bg-white text-sm w-64"
          />
        </div>
      </div>

      {/* Table with bordered rows */}
      <div className="bg-white rounded-lg shadow overflow-hidden border border-gray-300">
        <table className="min-w-full">
          <thead>
            <tr style={{ backgroundColor: '#e5e7eb', borderBottom: '2px solid #9ca3af' }}>
              <th
                onClick={() => handleSort('timestamp')}
                className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider cursor-pointer"
                style={{ borderRight: '1px solid #d1d5db' }}
                onMouseEnter={(e) => e.currentTarget.style.backgroundColor = '#d1d5db'}
                onMouseLeave={(e) => e.currentTarget.style.backgroundColor = 'transparent'}
              >
                Timestamp
              </th>
              <th
                onClick={() => handleSort('type')}
                className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider cursor-pointer"
                style={{ borderRight: '1px solid #d1d5db' }}
                onMouseEnter={(e) => e.currentTarget.style.backgroundColor = '#d1d5db'}
                onMouseLeave={(e) => e.currentTarget.style.backgroundColor = 'transparent'}
              >
                Type
              </th>
              <th
                onClick={() => handleSort('description')}
                className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider cursor-pointer"
                style={{ borderRight: '1px solid #d1d5db' }}
                onMouseEnter={(e) => e.currentTarget.style.backgroundColor = '#d1d5db'}
                onMouseLeave={(e) => e.currentTarget.style.backgroundColor = 'transparent'}
              >
                Description
              </th>
              <th
                onClick={() => handleSort('severity')}
                className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider cursor-pointer"
                style={{ borderRight: '1px solid #d1d5db' }}
                onMouseEnter={(e) => e.currentTarget.style.backgroundColor = '#d1d5db'}
                onMouseLeave={(e) => e.currentTarget.style.backgroundColor = 'transparent'}
              >
                Severity
              </th>
              <th
                onClick={() => handleSort('source_file')}
                className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider cursor-pointer"
                style={{ borderRight: '1px solid #d1d5db' }}
                onMouseEnter={(e) => e.currentTarget.style.backgroundColor = '#d1d5db'}
                onMouseLeave={(e) => e.currentTarget.style.backgroundColor = 'transparent'}
              >
                Source
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody className="bg-white">
            {isLoading ? (
              <tr style={{ borderBottom: '1px solid #cbd5e1' }}>
                <td colSpan={6} className="px-6 py-12 text-center text-gray-500">
                  Loading...
                </td>
              </tr>
            ) : paginatedAnomalies.length === 0 ? (
              <tr style={{ borderBottom: '1px solid #cbd5e1' }}>
                <td colSpan={6} className="px-6 py-12 text-center text-gray-500">
                  No anomalies found
                </td>
              </tr>
            ) : (
              paginatedAnomalies.map((anomaly) => (
                <tr 
                  key={anomaly.id} 
                  className="transition-colors duration-150"
                  style={{ borderBottom: '1px solid #cbd5e1' }}
                  onMouseEnter={(e) => e.currentTarget.style.backgroundColor = '#fef3c7'}
                  onMouseLeave={(e) => e.currentTarget.style.backgroundColor = 'white'}
                >
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900" style={{ borderRight: '1px solid #e5e7eb' }}>
                    {new Date(anomaly.timestamp).toLocaleString()}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900" style={{ borderRight: '1px solid #e5e7eb' }}>
                    {anomaly.type}
                  </td>
                  <td className="px-6 py-4 text-sm text-gray-900" style={{ borderRight: '1px solid #e5e7eb' }}>
                    {anomaly.description}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900" style={{ borderRight: '1px solid #e5e7eb' }}>
                    {anomaly.severity}
                  </td>
                  <td className="px-6 py-4 text-sm text-gray-500" style={{ borderRight: '1px solid #e5e7eb' }}>
                    {anomaly.source_file}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm">
                    <div className="flex items-center gap-2">
                      <button
                        onClick={() => handleGetRecommendations(anomaly)}
                        className="inline-flex items-center justify-center px-4 py-2 text-sm text-white bg-blue-500 border border-gray-300 rounded-full hover:bg-blue-600 transition-colors cursor-pointer"
                        style={{ fontFamily: 'Arial, sans-serif' }}
                      >
                        Recommend
                      </button>
                      <button
                        onClick={() => handleGetDetails(anomaly)}
                        className="inline-flex items-center justify-center px-4 py-2 text-sm text-white bg-blue-500 border border-gray-300 rounded-full hover:bg-blue-600 transition-colors cursor-pointer"
                        style={{ fontFamily: 'Arial, sans-serif' }}
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

        {/* Pagination */}
        <div className="px-6 py-4 bg-white border-t border-gray-200 flex items-center justify-between">
          <div className="text-sm text-gray-700">
            {filteredAndSortedAnomalies.length > 0 ? (
              <>Showing {startEntry} to {endEntry} of {filteredAndSortedAnomalies.length} entries</>
            ) : (
              <>Showing 0 entries</>
            )}
          </div>
          {totalPages > 1 && (
            <div className="flex items-center gap-1 flex-wrap">
              {/* Previous Button */}
              <button
                onClick={() => setCurrentPage(Math.max(1, currentPage - 1))}
                disabled={currentPage === 1}
                className={`px-3 py-1 text-sm rounded border ${
                  currentPage === 1
                    ? 'bg-gray-100 text-gray-400 border-gray-200 cursor-not-allowed'
                    : 'bg-white text-gray-700 border-gray-300 hover:bg-gray-50'
                }`}
              >
                Previous
              </button>

              {/* First Page */}
              {currentPage > 3 && (
                <>
                  <button
                    onClick={() => setCurrentPage(1)}
                    className="px-3 py-1 text-sm rounded bg-white text-gray-700 border border-gray-300 hover:bg-gray-50"
                  >
                    1
                  </button>
                  {currentPage > 4 && (
                    <span className="px-2 text-gray-500">...</span>
                  )}
                </>
              )}

              {/* Page Numbers Around Current */}
              {Array.from({ length: totalPages }, (_, i) => i + 1)
                .filter(pageNum => {
                  // Show current page and 2 pages before/after
                  return pageNum >= currentPage - 2 && pageNum <= currentPage + 2;
                })
                .map((pageNum) => (
                  <button
                    key={pageNum}
                    onClick={() => setCurrentPage(pageNum)}
                    className={`px-3 py-1 text-sm rounded ${
                      currentPage === pageNum
                        ? 'bg-blue-500 text-white'
                        : 'bg-white text-gray-700 border border-gray-300 hover:bg-gray-50'
                    }`}
                  >
                    {pageNum}
                  </button>
                ))}

              {/* Last Page */}
              {currentPage < totalPages - 2 && (
                <>
                  {currentPage < totalPages - 3 && (
                    <span className="px-2 text-gray-500">...</span>
                  )}
                  <button
                    onClick={() => setCurrentPage(totalPages)}
                    className="px-3 py-1 text-sm rounded bg-white text-gray-700 border border-gray-300 hover:bg-gray-50"
                  >
                    {totalPages}
                  </button>
                </>
              )}

              {/* Next Button */}
              <button
                onClick={() => setCurrentPage(Math.min(totalPages, currentPage + 1))}
                disabled={currentPage === totalPages}
                className={`px-3 py-1 text-sm rounded border ${
                  currentPage === totalPages
                    ? 'bg-gray-100 text-gray-400 border-gray-200 cursor-not-allowed'
                    : 'bg-white text-gray-700 border-gray-300 hover:bg-gray-50'
                }`}
              >
                Next
              </button>
            </div>
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
    </div>
  );
}
