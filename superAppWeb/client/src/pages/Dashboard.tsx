import { useState, useEffect } from "react";
import { useQuery, useMutation } from "@tanstack/react-query";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { apiRequest, queryClient } from "@/lib/queryClient";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Textarea } from "@/components/ui/textarea";
import { useToast } from "@/hooks/use-toast";
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";
import { Loader2, Send, RefreshCw, CheckCircle2, AlertCircle, Database, Sparkles, Wifi, WifiOff } from "lucide-react";
import { bedrockPromptSchema } from "@shared/schema";
import type { BedrockResponse, TimestreamQueryResponse } from "@shared/schema";

interface AWSHealth {
  status: string;
  aws: {
    region: string;
    accessKeyConfigured: boolean;
    secretKeyConfigured: boolean;
  };
}

export default function Dashboard() {
  const [aiResponse, setAiResponse] = useState("");
  const [isStreaming, setIsStreaming] = useState(false);
  const { toast } = useToast();

  // Form setup with validation
  const form = useForm({
    resolver: zodResolver(bedrockPromptSchema),
    defaultValues: {
      prompt: "",
    },
  });

  // Health check query
  const { data: healthData, isError: healthError } = useQuery<AWSHealth>({
    queryKey: ['/api/health'],
    refetchInterval: 10000, // Refresh every 10 seconds
  });

  // Fetch Timestream data on page load
  const { data: timestreamData, isLoading: timestreamLoading, error: timestreamError, refetch: refetchTimestream } = useQuery<TimestreamQueryResponse>({
    queryKey: ['/api/timestream/query'],
  });

  // Streaming GPT-OSS-120B response
  const handleStreamingChat = async (promptText: string) => {
    setIsStreaming(true);
    setAiResponse("");

    try {
      const response = await fetch('/api/bedrock/chat-stream', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ prompt: promptText }),
      });

      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.error || 'Failed to stream response');
      }

      const reader = response.body?.getReader();
      const decoder = new TextDecoder();

      if (!reader) {
        throw new Error('No response stream available');
      }

      let accumulatedResponse = "";

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        const chunk = decoder.decode(value, { stream: true });
        const lines = chunk.split('\n').filter(line => line.trim());

        for (const line of lines) {
          if (line.startsWith('data: ')) {
            const data = line.slice(6);
            if (data === '[DONE]') {
              continue;
            }
            try {
              const parsed = JSON.parse(data);
              if (parsed.chunk) {
                accumulatedResponse += parsed.chunk;
                setAiResponse(accumulatedResponse);
              }
            } catch (e) {
              console.error('Failed to parse chunk:', e);
            }
          }
        }
      }
    } catch (error) {
      toast({
        title: "Error",
        description: error instanceof Error ? error.message : "Failed to get response from GPT-OSS-120B",
        variant: "destructive",
      });
    } finally {
      setIsStreaming(false);
    }
  };

  const onSubmit = async (values: { prompt: string }) => {
    await handleStreamingChat(values.prompt);
  };

  const handleRefreshTimestream = () => {
    refetchTimestream();
  };

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="sticky top-0 z-50 border-b bg-card/95 backdrop-blur supports-[backdrop-filter]:bg-card/80">
        <div className="max-w-7xl mx-auto px-6 py-4">
          <div className="flex items-center justify-between gap-4 flex-wrap">
            <div className="flex items-center gap-3">
              <div className="p-2 rounded-lg bg-primary/10" data-testid="icon-dashboard-logo">
                <Database className="h-6 w-6 text-primary" />
              </div>
              <div>
                <h1 className="text-xl font-semibold text-foreground" data-testid="text-dashboard-title">AWS Integration Dashboard</h1>
                <p className="text-xs text-muted-foreground" data-testid="text-account-id">Account: 012351853258</p>
              </div>
            </div>
            
            {/* Connection Status */}
            <div className="flex items-center gap-4" data-testid="container-connection-status">
              <div className="flex items-center gap-2 text-sm">
                {healthError ? (
                  <div className="flex items-center gap-1.5" data-testid="status-aws-error">
                    <WifiOff className="h-4 w-4 text-destructive" />
                    <span className="text-destructive font-medium">Disconnected</span>
                  </div>
                ) : healthData?.aws.accessKeyConfigured && healthData?.aws.secretKeyConfigured ? (
                  <>
                    <div className="flex items-center gap-1.5" data-testid="status-bedrock-connected">
                      <div className="h-2 w-2 rounded-full bg-status-online animate-pulse" />
                      <span className="text-muted-foreground">Bedrock</span>
                    </div>
                    <div className="flex items-center gap-1.5" data-testid="status-timestream-connected">
                      <div className="h-2 w-2 rounded-full bg-status-online animate-pulse" />
                      <span className="text-muted-foreground">Timestream</span>
                    </div>
                    <span className="text-xs text-muted-foreground" data-testid="text-aws-region">
                      {healthData?.aws.region}
                    </span>
                  </>
                ) : (
                  <div className="flex items-center gap-1.5" data-testid="status-aws-pending">
                    <div className="h-2 w-2 rounded-full bg-status-away animate-pulse" />
                    <span className="text-muted-foreground">Configuring...</span>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-6 py-8">
        <div className="space-y-8">
          {/* GPT-OSS-120B Input Section */}
          <Card className="shadow-md" data-testid="card-bedrock-input">
            <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0 pb-4">
              <div className="flex items-center gap-2">
                <Sparkles className="h-5 w-5 text-primary" data-testid="icon-bedrock-header" />
                <div>
                  <h2 className="text-xl font-semibold" data-testid="text-bedrock-header">Send Prompt to GPT-OSS-120B</h2>
                  <p className="text-sm text-muted-foreground mt-0.5" data-testid="text-bedrock-subtitle">AWS Bedrock AI Integration</p>
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <Form {...form}>
                <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
                  <FormField
                    control={form.control}
                    name="prompt"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel className="text-sm font-medium uppercase tracking-wide" data-testid="label-prompt">
                          Your Prompt
                        </FormLabel>
                        <FormControl>
                          <Textarea
                            {...field}
                            data-testid="input-prompt"
                            placeholder="Ask GPT-OSS-120B anything... (e.g., 'Explain quantum computing in simple terms')"
                            className="min-h-32 resize-vertical font-mono text-base p-4"
                            disabled={isStreaming}
                          />
                        </FormControl>
                        <div className="flex items-center justify-between">
                          <FormMessage data-testid="text-form-error" />
                          <p className="text-xs text-muted-foreground" data-testid="text-character-count">
                            {field.value.length} / 10000 characters
                          </p>
                        </div>
                      </FormItem>
                    )}
                  />

                  <div className="flex gap-2">
                    <Button
                      type="submit"
                      data-testid="button-submit-prompt"
                      disabled={isStreaming || !form.watch("prompt").trim()}
                      className="px-8"
                    >
                      {isStreaming ? (
                        <>
                          <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                          Processing...
                        </>
                      ) : (
                        <>
                          <Send className="mr-2 h-4 w-4" />
                          Submit
                        </>
                      )}
                    </Button>
                    {form.watch("prompt") && (
                      <Button
                        type="button"
                        variant="outline"
                        data-testid="button-clear-prompt"
                        onClick={() => form.reset()}
                        disabled={isStreaming}
                      >
                        Clear
                      </Button>
                    )}
                  </div>
                </form>
              </Form>
            </CardContent>
          </Card>

          {/* Response Areas - Two Column Layout */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* GPT-OSS-120B Response */}
            <Card className="shadow-md" data-testid="card-claude-response">
              <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0 pb-4">
                <div>
                  <h2 className="text-xl font-semibold" data-testid="text-claude-header">AI Response</h2>
                  {aiResponse && !isStreaming && (
                    <p className="text-xs text-muted-foreground mt-0.5" data-testid="text-claude-timestamp">
                      Last updated: {new Date().toLocaleString()}
                    </p>
                  )}
                </div>
                {aiResponse && !isStreaming && (
                  <CheckCircle2 className="h-5 w-5 text-status-online" data-testid="icon-claude-success" />
                )}
                {isStreaming && (
                  <Loader2 className="h-5 w-5 animate-spin text-primary" data-testid="icon-claude-streaming" />
                )}
              </CardHeader>
              <CardContent>
                <div className="relative">
                  <Textarea
                    data-testid="textarea-claude-response"
                    readOnly
                    value={
                      isStreaming && !aiResponse
                        ? "GPT-OSS-120B is thinking..."
                        : aiResponse || ""
                    }
                    placeholder="Response will appear here..."
                    className="min-h-48 font-mono text-sm resize-none bg-muted/30"
                  />
                  {isStreaming && aiResponse && (
                    <div className="absolute bottom-2 right-2">
                      <div className="flex items-center gap-2 bg-primary/10 px-2 py-1 rounded text-xs text-primary">
                        <Loader2 className="h-3 w-3 animate-spin" />
                        <span data-testid="text-streaming-indicator">Streaming...</span>
                      </div>
                    </div>
                  )}
                </div>
              </CardContent>
            </Card>

            {/* Timestream DB Response */}
            <Card className="shadow-md" data-testid="card-timestream-response">
              <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0 pb-4">
                <div>
                  <h2 className="text-xl font-semibold" data-testid="text-timestream-header">Timestream UEReports Data</h2>
                  {timestreamData?.lastUpdated && (
                    <p className="text-xs text-muted-foreground mt-0.5" data-testid="text-timestream-timestamp">
                      Last updated: {new Date(timestreamData.lastUpdated).toLocaleString()}
                    </p>
                  )}
                </div>
                <Button
                  size="icon"
                  variant="ghost"
                  data-testid="button-refresh-timestream"
                  onClick={handleRefreshTimestream}
                  disabled={timestreamLoading}
                >
                  <RefreshCw className={`h-4 w-4 ${timestreamLoading ? 'animate-spin' : ''}`} data-testid="icon-refresh-timestream" />
                </Button>
              </CardHeader>
              <CardContent>
                <div className="relative">
                  {timestreamLoading ? (
                    <div className="min-h-48 flex items-center justify-center bg-muted/30 rounded-lg" data-testid="container-timestream-loading">
                      <div className="flex flex-col items-center gap-2">
                        <Loader2 className="h-8 w-8 animate-spin text-primary" data-testid="icon-timestream-loading" />
                        <p className="text-sm text-muted-foreground" data-testid="text-timestream-loading">Loading Timestream data...</p>
                      </div>
                    </div>
                  ) : timestreamError ? (
                    <div className="min-h-48 flex items-center justify-center bg-destructive/10 border border-destructive/20 rounded-lg p-6" data-testid="container-timestream-error">
                      <div className="flex flex-col items-center gap-2 text-center">
                        <AlertCircle className="h-8 w-8 text-destructive" data-testid="icon-timestream-error" />
                        <p className="text-sm text-destructive font-medium" data-testid="text-timestream-error-title">Failed to load Timestream data</p>
                        <p className="text-xs text-muted-foreground max-w-xs" data-testid="text-timestream-error-message">
                          {timestreamError instanceof Error ? timestreamError.message : "Unknown error occurred"}
                        </p>
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={handleRefreshTimestream}
                          className="mt-2"
                          data-testid="button-retry-timestream"
                        >
                          Try Again
                        </Button>
                      </div>
                    </div>
                  ) : timestreamData && timestreamData.records.length > 0 ? (
                    <div className="space-y-3" data-testid="container-timestream-table">
                      <div className="overflow-auto max-h-96 rounded-lg border">
                        <table className="w-full text-sm" data-testid="table-timestream-data">
                          <thead className="bg-muted sticky top-0">
                            <tr>
                              {timestreamData.columnInfo.map((col) => (
                                <th key={col.name} className="px-4 py-2 text-left font-medium text-foreground" data-testid={`header-${col.name}`}>
                                  {col.name}
                                </th>
                              ))}
                            </tr>
                          </thead>
                          <tbody className="divide-y">
                            {timestreamData.records.map((record, idx) => (
                              <tr key={idx} className="hover-elevate" data-testid={`row-timestream-${idx}`}>
                                {timestreamData.columnInfo.map((col) => (
                                  <td key={col.name} className="px-4 py-2 font-mono text-xs" data-testid={`cell-${idx}-${col.name}`}>
                                    {record[col.name] !== null ? String(record[col.name]) : '-'}
                                  </td>
                                ))}
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                      <p className="text-xs text-muted-foreground text-center" data-testid="text-timestream-record-count">
                        Showing {timestreamData.records.length} record{timestreamData.records.length !== 1 ? 's' : ''}
                      </p>
                    </div>
                  ) : (
                    <div className="min-h-48 flex items-center justify-center bg-muted/30 rounded-lg" data-testid="container-timestream-empty">
                      <div className="flex flex-col items-center gap-2 text-center max-w-xs">
                        <Database className="h-8 w-8 text-muted-foreground/50" data-testid="icon-timestream-empty" />
                        <p className="text-sm text-muted-foreground font-medium" data-testid="text-timestream-empty-title">No data available</p>
                        <p className="text-xs text-muted-foreground" data-testid="text-timestream-empty-message">
                          The UEReports table is empty or no records match the query
                        </p>
                      </div>
                    </div>
                  )}
                </div>
              </CardContent>
            </Card>
          </div>
        </div>
      </main>
    </div>
  );
}
