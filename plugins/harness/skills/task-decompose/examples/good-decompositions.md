# Example: Adding OAuth2 to an Express App

## Unit 1: OAuth Configuration
- Files: `src/config/oauth.ts`, `.env.example`
- Criteria: OAuth config loads from env vars, validates required fields
- Depends on: none
- Verify: `npm test -- --grep 'oauth config'`

## Unit 2: OAuth Routes
- Files: `src/routes/auth/oauth.ts`, `src/routes/auth/callback.ts`
- Criteria: GET /auth/google redirects to Google, GET /auth/callback handles response
- Depends on: Unit 1
- Verify: `npm test -- --grep 'oauth routes'`

## Unit 3: Session Integration
- Files: `src/middleware/session.ts`, `src/models/user.ts`
- Criteria: OAuth user is created/found, session is established
- Depends on: Unit 2
- Verify: `npm test -- --grep 'oauth session'`

## Unit 4: Frontend Integration
- Files: `src/components/LoginButton.tsx`, `src/hooks/useAuth.ts`
- Criteria: Google login button appears, redirects correctly, shows user after login
- Depends on: Unit 3
- Verify: `npm test -- --grep 'login button'` + Chrome visual check

## Unit 5: Integration Tests
- Files: `tests/integration/oauth.test.ts`
- Criteria: Full OAuth flow works end-to-end
- Depends on: Units 1-4
- Verify: `npm test -- --grep 'oauth integration'`
