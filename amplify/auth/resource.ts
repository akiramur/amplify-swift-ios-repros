import { defineAuth } from "@aws-amplify/backend";
export const auth = defineAuth({
  loginWith: {
    email: true,
    externalProviders: {
      callbackUrls: ["amplifyswiftreprolab://callback/"],
      logoutUrls: ["amplifyswiftreprolab://signout/"],
    },
  },
});
