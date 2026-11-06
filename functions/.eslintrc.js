module.exports = {
  root: true,
  env: {
    es6: true,
    node: true,
  },
  extends: [
    "eslint:recommended",
    "google",
    "plugin:@typescript-eslint/recommended",
  ],
  parser: "@typescript-eslint/parser",
  parserOptions: {
    project: ["tsconfig.json", "tsconfig.dev.json"],
    sourceType: "module",
  },
  ignorePatterns: [
    "/lib/**/*",
    "/generated/**/*",
    "jest.config.js",
    "jest.rules.config.js",
    ".eslintrc.js",
  ],
  plugins: [
    "@typescript-eslint",
    "import",
  ],
  rules: {
    "quotes": ["error", "double"],
    "import/no-unresolved": 0,
    "indent": ["error", 2],
    // firebase-functions logger 는 마지막 인자가 plain object 일 때만 그것을
    // 구조화 필드로 남기고, 앞자리 객체는 message 문자열에 녹인다.
    // logger.write(entry) 는 첫 인자가 entry 객체인 정상 API 라 level 메서드만 잡는다.
    "no-restricted-syntax": [
      "error",
      {
        selector:
          "CallExpression[callee.object.name='logger']" +
          "[callee.property.name=/^(debug|info|log|warn|error)$/]" +
          "[arguments.0.type='ObjectExpression']",
        message:
          "logger 호출은 (메시지, 필드) 순서로 쓴다 — firebase-functions " +
          "logger 는 마지막 인자 객체만 Cloud Logging jsonPayload 필드로 남긴다.",
      },
    ],
  },
};
