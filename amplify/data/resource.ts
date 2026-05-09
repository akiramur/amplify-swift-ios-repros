import { a, defineData, type ClientSchema } from "@aws-amplify/backend";

const schema = a.schema({
  ReproItem: a
    .model({
      content: a.string().required(),
      createdByDevice: a.string(),
    })
    .authorization((allow) => [allow.authenticated()]),
});

export type Schema = ClientSchema<typeof schema>;

export const data = defineData({
  schema,
  authorizationModes: {
    defaultAuthorizationMode: "userPool",
  },
});
