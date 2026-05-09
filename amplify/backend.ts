import { defineBackend } from "@aws-amplify/backend";

import { auth } from "./auth/resource";
import { data } from "./data/resource";
import { failHostedUISignUp } from "./functions/failHostedUISignUp/resource";

defineBackend({
  auth,
  data,
  failHostedUISignUp,
});
