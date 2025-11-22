import "../styles/global.css";
import React from "react";
import Navigation from "@/components/navigation";

export const metadata = {
  title: "movieClone",
};

export default function Layout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Navigation></Navigation>
        {children}
      </body>
    </html>
  );
}
