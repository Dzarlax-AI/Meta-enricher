"use strict";

const { execSync } = require("child_process");
const path = require("path");

exports.default = async function notarize({ appOutDir, packager }) {
  if (packager.platform.name !== "mac") return;

  const appName = packager.appInfo.productFilename;
  const appPath = path.join(appOutDir, `${appName}.app`);

  console.log(`\n  • notarizing  file=${appPath}`);

  // Zip the app for submission
  const zipPath = path.join(appOutDir, `${appName}.zip`);
  execSync(`ditto -c -k --sequesterRsrc --keepParent "${appPath}" "${zipPath}"`);

  // Submit for notarization and wait
  execSync(
    `xcrun notarytool submit "${zipPath}" --keychain-profile "meta-enricher" --wait`,
    { stdio: "inherit" }
  );

  // Staple the ticket
  execSync(`xcrun stapler staple "${appPath}"`, { stdio: "inherit" });

  // Clean up zip
  execSync(`rm -f "${zipPath}"`);

  console.log("  • notarization complete");
};
