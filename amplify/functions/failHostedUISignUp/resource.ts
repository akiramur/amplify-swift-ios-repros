import { defineFunction } from "@aws-amplify/backend";

export const failHostedUISignUp = defineFunction({
  name: "failHostedUISignUp",
  entry: "./handler.ts",
  runtime: 20,
  resourceGroupName: "auth",
});
