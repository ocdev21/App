#!/usr/bin/env python3
import os
import sys
from flask import Flask, request, jsonify
from flask_cors import CORS
from rag_service import rag_service
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy", "service": "RAG"}), 200

@app.route('/rag/stats', methods=['GET'])
def get_stats():
    try:
        stats = rag_service.get_stats()
        return jsonify(stats), 200
    except Exception as e:
        logger.error(f"Error getting RAG stats: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/rag/add-document', methods=['POST'])
def add_document():
    try:
        data = request.json
        
        required_fields = ['anomaly_id', 'anomaly_type', 'severity', 'error_log', 'recommendation']
        for field in required_fields:
            if field not in data:
                return jsonify({"error": f"Missing required field: {field}"}), 400
        
        doc_id = rag_service.add_document(
            anomaly_id=data['anomaly_id'],
            anomaly_type=data['anomaly_type'],
            severity=data['severity'],
            error_log=data['error_log'],
            recommendation=data['recommendation'],
            resolution_notes=data.get('resolution_notes'),
            metadata=data.get('metadata')
        )
        
        return jsonify({
            "success": True,
            "document_id": doc_id,
            "message": "Document added to knowledge base"
        }), 201
        
    except Exception as e:
        logger.error(f"Error adding document: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/rag/search', methods=['POST'])
def search_similar():
    try:
        data = request.json
        
        if 'query_text' not in data:
            return jsonify({"error": "Missing query_text field"}), 400
        
        results = rag_service.search_similar_anomalies(
            query_text=data['query_text'],
            n_results=data.get('n_results', 3),
            anomaly_type_filter=data.get('anomaly_type_filter')
        )
        
        return jsonify({
            "success": True,
            "results": results,
            "count": len(results)
        }), 200
        
    except Exception as e:
        logger.error(f"Error searching: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/rag/get-context', methods=['POST'])
def get_context():
    try:
        data = request.json
        
        if 'anomaly_type' not in data or 'error_log' not in data:
            return jsonify({"error": "Missing anomaly_type or error_log"}), 400
        
        context = rag_service.get_context_for_recommendation(
            anomaly_type=data['anomaly_type'],
            error_log=data['error_log'],
            n_results=data.get('n_results', 3)
        )
        
        return jsonify({
            "success": True,
            "context": context,
            "has_context": len(context) > 0
        }), 200
        
    except Exception as e:
        logger.error(f"Error getting context: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/rag/upload-file', methods=['POST'])
def upload_file():
    try:
        if 'file' not in request.files:
            return jsonify({"error": "No file provided"}), 400
        
        file = request.files['file']
        
        if file.filename == '':
            return jsonify({"error": "No file selected"}), 400
        
        # Read file content
        file_content = file.read()
        filename = file.filename
        file_type = file.content_type or 'application/octet-stream'
        
        # Validate file type
        allowed_extensions = ['.pdf', '.txt', '.md']
        if not any(filename.lower().endswith(ext) for ext in allowed_extensions):
            return jsonify({
                "error": f"Unsupported file type. Allowed: {', '.join(allowed_extensions)}"
            }), 400
        
        # Add to knowledge base
        doc_id = rag_service.add_general_document(
            file_content=file_content,
            filename=filename,
            file_type=file_type,
            metadata=request.form.to_dict()
        )
        
        return jsonify({
            "success": True,
            "document_id": doc_id,
            "filename": filename,
            "message": f"Document '{filename}' uploaded successfully"
        }), 201
        
    except Exception as e:
        logger.error(f"Error uploading file: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/rag/delete-document/<anomaly_id>', methods=['DELETE'])
def delete_document(anomaly_id):
    try:
        success = rag_service.delete_document(anomaly_id)
        
        if success:
            return jsonify({
                "success": True,
                "message": f"Document {anomaly_id} deleted"
            }), 200
        else:
            return jsonify({
                "success": False,
                "message": "Document not found or deletion failed"
            }), 404
            
    except Exception as e:
        logger.error(f"Error deleting document: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/rag/reset', methods=['POST'])
def reset_collection():
    try:
        rag_service.reset_collection()
        return jsonify({
            "success": True,
            "message": "Knowledge base reset successfully"
        }), 200
    except Exception as e:
        logger.error(f"Error resetting collection: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    port = int(os.environ.get('RAG_PORT', 8001))
    logger.info(f"Starting RAG service on port {port}")
    logger.info(f"ChromaDB storage: {rag_service.persist_directory}")
    logger.info(f"Knowledge base size: {rag_service.collection.count()} documents")
    
    app.run(host='0.0.0.0', port=port, debug=False)
