# Cloud Functions (functions/)

**패키지 매니저 컨벤션 (필수):** `functions/` 디렉토리는 **pnpm + corepack** 만 사용. `package.json` 의 `packageManager` 필드 (예: `pnpm@10.33.2`) 가 corepack 으로 자동 핀. lockfile 은 `pnpm-lock.yaml` (`package-lock.json` 금지). clone 직후 1회 `corepack enable` 후 `cd functions && pnpm install`. 모든 Cloud Functions 빌드/배포 명령은 `pnpm <script>` (예: `pnpm build`, `pnpm test`) 사용.
