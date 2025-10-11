# Fix for ChromaDB SQLite version requirement (requires pysqlite3-binary)
import sys
__import__('pysqlite3')
sys.modules['sqlite3'] = sys.modules.pop('pysqlite3')

import os
import chromadb
from chromadb.config import Settings
from sentence_transformers import SentenceTransformer
from typing import List, Dict, Optional
import json
from datetime import datetime
import PyPDF2
import io

class RAGService:
    def __init__(self, persist_directory: str = None):
        # Use environment variable or /pvc/chromadb in production (Kubernetes), local directory in development
        if persist_directory is None:
            persist_directory = os.environ.get('CHROMADB_PERSIST_DIR')
            if persist_directory is None:
                if os.path.exists('/pvc'):
                    persist_directory = '/pvc/chromadb'
                else:
                    persist_directory = './data/chromadb'
        
        self.persist_directory = persist_directory
        os.makedirs(persist_directory, exist_ok=True)
        
        # Setup uploaded files directory
        self.uploaded_docs_dir = os.environ.get('UPLOADED_DOCS_DIR')
        if self.uploaded_docs_dir is None:
            if os.path.exists('/pvc'):
                self.uploaded_docs_dir = '/pvc/uploaded_docs'
            else:
                self.uploaded_docs_dir = './data/uploaded_docs'
        os.makedirs(self.uploaded_docs_dir, exist_ok=True)
        
        self.client = chromadb.PersistentClient(
            path=persist_directory,
            settings=Settings(
                anonymized_telemetry=False,
                allow_reset=True
            )
        )
        
        self.embedding_model = SentenceTransformer('all-MiniLM-L6-v2')
        
        self.collection = self.client.get_or_create_collection(
            name="anomaly_knowledge_base",
            metadata={"description": "L1 network anomaly resolution knowledge base"}
        )
        
        print(f"[RAG] Initialized with {self.collection.count()} documents in knowledge base")
    
    def embed_text(self, text: str) -> List[float]:
        embedding = self.embedding_model.encode(text, convert_to_numpy=True)
        return embedding.tolist()
    
    def add_document(
        self,
        anomaly_id: str,
        anomaly_type: str,
        severity: str,
        error_log: str,
        recommendation: str,
        resolution_notes: Optional[str] = None,
        metadata: Optional[Dict] = None
    ) -> str:
        combined_text = f"""
Anomaly Type: {anomaly_type}
Severity: {severity}
Error Log: {error_log}
Recommendation: {recommendation}
{f'Resolution Notes: {resolution_notes}' if resolution_notes else ''}
        """.strip()
        
        embedding = self.embed_text(combined_text)
        
        doc_metadata = {
            "anomaly_id": anomaly_id,
            "anomaly_type": anomaly_type,
            "severity": severity,
            "error_log": error_log,
            "recommendation": recommendation,
            "resolution_notes": resolution_notes or "",
            "document_type": "anomaly",
            "indexed_at": datetime.now().isoformat(),
            **(metadata or {})
        }
        
        self.collection.add(
            ids=[anomaly_id],
            embeddings=[embedding],
            documents=[combined_text],
            metadatas=[doc_metadata]
        )
        
        print(f"[RAG] Added document for anomaly {anomaly_id} to knowledge base")
        return anomaly_id
    
    def search_similar_anomalies(
        self,
        query_text: str,
        n_results: int = 3,
        anomaly_type_filter: Optional[str] = None
    ) -> List[Dict]:
        query_embedding = self.embed_text(query_text)
        
        where_clause = {}
        if anomaly_type_filter:
            where_clause["anomaly_type"] = anomaly_type_filter
        
        results = self.collection.query(
            query_embeddings=[query_embedding],
            n_results=n_results,
            where=where_clause if where_clause else None
        )
        
        formatted_results = []
        if results and results['ids'] and len(results['ids'][0]) > 0:
            for i in range(len(results['ids'][0])):
                formatted_results.append({
                    "anomaly_id": results['ids'][0][i],
                    "distance": results['distances'][0][i] if 'distances' in results else None,
                    "metadata": results['metadatas'][0][i] if 'metadatas' in results else {},
                    "document": results['documents'][0][i] if 'documents' in results else ""
                })
        
        print(f"[RAG] Found {len(formatted_results)} similar anomalies for query")
        return formatted_results
    
    def get_context_for_recommendation(
        self,
        anomaly_type: str,
        error_log: str,
        n_results: int = 3
    ) -> str:
        query_text = f"Anomaly Type: {anomaly_type}\nError Log: {error_log}"
        
        similar_cases = self.search_similar_anomalies(
            query_text=query_text,
            n_results=n_results,
            anomaly_type_filter=anomaly_type
        )
        
        if not similar_cases:
            return ""
        
        context_parts = ["### Similar Past Cases:\n"]
        for i, case in enumerate(similar_cases, 1):
            meta = case['metadata']
            context_parts.append(f"""
**Case {i}** (Anomaly ID: {case['anomaly_id']}, Similarity: {1 - case.get('distance', 0):.2%}):
- Severity: {meta.get('severity', 'N/A')}
- Error Log: {meta.get('error_log', 'N/A')}
- Past Recommendation: {meta.get('recommendation', 'N/A')}
- Resolution Notes: {meta.get('resolution_notes', 'No resolution notes available')}
""")
        
        context_text = "\n".join(context_parts)
        print(f"[RAG] Generated context with {len(similar_cases)} similar cases")
        return context_text
    
    def delete_document(self, anomaly_id: str) -> bool:
        try:
            self.collection.delete(ids=[anomaly_id])
            print(f"[RAG] Deleted document for anomaly {anomaly_id}")
            return True
        except Exception as e:
            print(f"[RAG] Error deleting document {anomaly_id}: {e}")
            return False
    
    def add_general_document(
        self,
        file_content: bytes,
        filename: str,
        file_type: str,
        metadata: Optional[Dict] = None
    ) -> str:
        """
        Add a general document (PDF, TXT, MD) to the knowledge base
        """
        text_content = ""
        
        # Extract text based on file type
        if file_type == 'application/pdf' or filename.endswith('.pdf'):
            pdf_reader = PyPDF2.PdfReader(io.BytesIO(file_content))
            text_pages = []
            for page in pdf_reader.pages:
                page_text = page.extract_text()
                # Handle cases where extract_text() returns None
                if page_text:
                    text_pages.append(page_text)
            text_content = "\n".join(text_pages)
        
        elif file_type.startswith('text/') or filename.endswith(('.txt', '.md')):
            text_content = file_content.decode('utf-8', errors='ignore')
        
        else:
            raise ValueError(f"Unsupported file type: {file_type}")
        
        if not text_content.strip():
            raise ValueError("No text content could be extracted from the file")
        
        # Generate unique ID based on filename and timestamp
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        doc_id = f"doc_{filename}_{timestamp}"
        
        # Save original file to disk with sanitized filename (prevent path traversal)
        # Use only the basename to strip any directory components
        safe_filename = f"{timestamp}_{os.path.basename(filename)}"
        file_path = os.path.join(self.uploaded_docs_dir, safe_filename)
        
        try:
            with open(file_path, 'wb') as f:
                f.write(file_content)
            print(f"[RAG] Saved original file to {file_path}")
        except Exception as e:
            print(f"[RAG] Warning: Failed to save original file: {e}")
            file_path = None
        
        # Create embedding
        embedding = self.embed_text(text_content)
        
        # Prepare metadata
        doc_metadata = {
            "filename": filename,
            "file_type": file_type,
            "document_type": "general",
            "indexed_at": datetime.now().isoformat(),
            "content_preview": text_content[:200] + "..." if len(text_content) > 200 else text_content,
            "file_path": file_path,
            "has_original_file": file_path is not None,
            **(metadata or {})
        }
        
        # Add to collection
        self.collection.add(
            ids=[doc_id],
            embeddings=[embedding],
            documents=[text_content],
            metadatas=[doc_metadata]
        )
        
        print(f"[RAG] Added general document '{filename}' to knowledge base")
        return doc_id
    
    def get_stats(self) -> Dict:
        total_count = self.collection.count()
        
        # Count anomaly cases (fetch ALL documents with proper limit)
        try:
            anomaly_results = self.collection.get(
                where={"document_type": "anomaly"},
                limit=total_count if total_count > 0 else 1
            )
            anomaly_count = len(anomaly_results['ids']) if anomaly_results and 'ids' in anomaly_results else 0
        except:
            anomaly_count = 0
        
        # Count general documents (fetch ALL documents with proper limit)
        try:
            general_results = self.collection.get(
                where={"document_type": "general"},
                limit=total_count if total_count > 0 else 1
            )
            general_count = len(general_results['ids']) if general_results and 'ids' in general_results else 0
        except:
            general_count = 0
        
        # Count documents with original files stored (fetch ALL with proper limit)
        try:
            all_docs = self.collection.get(limit=total_count if total_count > 0 else 1)
            stored_files_count = 0
            if all_docs and 'metadatas' in all_docs:
                for meta in all_docs['metadatas']:
                    if meta.get('has_original_file') or meta.get('file_path'):
                        stored_files_count += 1
        except:
            stored_files_count = 0
        
        return {
            "total_documents": total_count,
            "anomaly_cases": anomaly_count,
            "general_documents": general_count,
            "stored_files": stored_files_count,
            "collection_name": self.collection.name,
            "persist_directory": self.persist_directory
        }
    
    def reset_collection(self):
        self.client.delete_collection(name="anomaly_knowledge_base")
        self.collection = self.client.get_or_create_collection(
            name="anomaly_knowledge_base",
            metadata={"description": "L1 network anomaly resolution knowledge base"}
        )
        print("[RAG] Knowledge base reset")


rag_service = RAGService()

if __name__ == "__main__":
    print("RAG Service initialized")
    print(f"Stats: {rag_service.get_stats()}")
