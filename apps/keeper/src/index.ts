import { loadConfig } from "./config.js";
import { TempestKeeper } from "./keeper.js";

async function main() {
  const config = loadConfig();
  const keeper = new TempestKeeper(config);

  // Graceful shutdown
  process.on("SIGINT", () => {
    console.log("\nShutting down...");
    keeper.stop();
    process.exit(0);
  });

  process.on("SIGTERM", () => {
    keeper.stop();
    process.exit(0);
  });

  await keeper.start();
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
