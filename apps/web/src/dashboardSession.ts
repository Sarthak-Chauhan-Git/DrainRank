import { createContext } from "react";

export const DashboardSessionContext = createContext<{
  email: string;
} | null>(null);
