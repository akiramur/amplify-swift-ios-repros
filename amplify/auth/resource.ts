import { defineAuth } from "@aws-amplify/backend";
import { failHostedUISignUp } from "../functions/failHostedUISignUp/resource";

export const auth = defineAuth({
  triggers: {
    preSignUp: failHostedUISignUp,
  },
  loginWith: {
    email: true,
    externalProviders: {
      callbackUrls: ["amplifyswiftreprolab://callback/"],
      logoutUrls: ["amplifyswiftreprolab://signout/"],
    },
  },
});
