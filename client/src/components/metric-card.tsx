import { LucideIcon } from "lucide-react";

interface MetricCardProps {
  title: string;
  value: string | number;
  change: string;
  changeType: "positive" | "negative";
  icon: LucideIcon;
  iconColor: "red" | "blue" | "green" | "purple";
}

export default function MetricCard({
  title,
  value,
  change,
  changeType,
  icon: Icon,
  iconColor,
}: MetricCardProps) {
  const changeColorClass = changeType === "positive" ? "text-green-600" : "text-red-600";

  return (
    <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
      <div className="flex items-start justify-between">
        <div className="flex-1">
          <p className="text-sm font-medium text-gray-500 uppercase tracking-wide mb-2">
            {title}
          </p>
          <p className="text-3xl font-bold text-gray-900 mb-3">{value}</p>
          <div className="flex items-center">
            <span className={`text-sm font-medium ${changeColorClass}`}>
              {change}
            </span>
            <span className="text-gray-500 text-sm ml-1">from last</span>
            <span className="text-gray-500 text-sm ml-1">week</span>
          </div>
        </div>
        <div className={`metric-icon ${iconColor} ml-4`}>
          <Icon className="w-6 h-6" />
        </div>
      </div>
    </div>
  );
}
