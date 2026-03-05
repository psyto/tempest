import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Tempest Dashboard",
  description: "Volatility-responsive dynamic fee hook for Uniswap v4",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="dark">
      <body className="min-h-screen bg-[var(--bg-primary)] antialiased">
        {children}
      </body>
    </html>
  );
}
