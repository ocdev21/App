import { Switch, Route } from "wouter";
import { queryClient } from "./lib/queryClient";
import { QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "@/components/ui/toaster";
import Dashboard from "./pages/dashboard";
import Anomalies from "./pages/anomalies";
import RecommendationsWindow from "./pages/recommendations-window";
import DetailsWindow from "./pages/details-window";
import Sidebar from "./components/sidebar";
import Header from "./components/header";
import { useState } from "react";

function Router() {
  return (
    <Switch>
      <Route path="/recommendations-window" component={RecommendationsWindow} />
      <Route path="/details-window" component={DetailsWindow} />
      <Route path="/" component={Dashboard} />
      <Route path="/dashboard" component={Dashboard} />
      <Route path="/anomalies" component={Anomalies} />
      <Route><Dashboard /></Route>
    </Switch>
  );
}

function App() {
  const [currentPage, setCurrentPage] = useState("Dashboard");

  return (
    <QueryClientProvider client={queryClient}>
      <Switch>
        <Route path="/recommendations-window">
          <RecommendationsWindow />
        </Route>
        <Route path="/details-window">
          <DetailsWindow />
        </Route>
        <Route>
          <div className="min-h-screen bg-gray-50">
            <Sidebar setCurrentPage={setCurrentPage} />
            <div className="main-content-ml">
              <Header currentPage={currentPage} />
              <Router />
            </div>
          </div>
        </Route>
      </Switch>
      <Toaster />
    </QueryClientProvider>
  );
}

export default App;
