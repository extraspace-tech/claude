# S0-5 admin-ui toolchain spike (2026-10-13)

Project: `admin-ui/` in this folder (left in place, `npm ci` works from `package-lock.json`). Node 24.18.0, npm 11.16.0.
Everything below was run here. Final state: `tsc -b` OK, `vite build` OK, `vitest run` 4/4 pass, `openapi-typescript` OK.

## Installed versions (`npm ls --depth=0`)
```
├── @fontsource-variable/geist@5.3.0
├── @hookform/resolvers@5.9.1
├── @tailwindcss/vite@4.3.3
├── @tanstack/react-query@5.104.2
├── @tanstack/react-table@9.3.1
├── @testing-library/jest-dom@7.0.1
├── @testing-library/react@16.3.3
├── @testing-library/user-event@14.6.8
├── @types/node@26.6.5
├── @types/react-dom@19.3.0
├── @types/react@19.3.0
├── @vitejs/plugin-react@6.1.2
├── class-variance-authority@0.7.1
├── cn@0.4.0
├── jsdom@30.1.2
├── lucide-react@1.56.0
├── msw@3.0.3
├── next-themes@0.4.6
├── openapi-fetch@0.17.0
├── openapi-typescript@7.13.0
├── radix-ui@1.8.1
├── react-dom@19.3.0
├── react-hook-form@7.90.0
├── react-router@8.4.0
├── react@19.3.0
├── shadcn@4.21.4
├── sonner@2.0.8
├── tailwindcss@4.3.3
├── tw-animate-css@1.4.0
├── typescript@6.0.3
├── vite@8.3.4
├── vitest@5.0.4
└── zod@4.6.7
```

All versions in the task list resolved exactly as given, except `typescript` (see Q1). shadcn added: `radix-ui 1.8.1`, `class-variance-authority 0.7.1`, `cn 0.4.0` (replaces clsx + tailwind-merge in the new preset), `lucide-react 1.56.0`, `tw-animate-css 1.4.0`, `@fontsource-variable/geist 5.3.0`, `shadcn 4.21.4` (a runtime dep: `index.css` imports `shadcn/tailwind.css`), `sonner 2.0.8`, `next-themes 0.4.6`. `package.json` uses caret ranges; pin exact versions in the real project (the lockfile pins them anyway).

## Q1. TypeScript version: pin 6.0.3
| TS | tsc -b | vite build | vitest | openapi-typescript 7.13.0 CLI |
|---|---|---|---|---|
| 7.0.2 | OK | OK | OK (4/4) | FAILS: `TypeError: Cannot read properties of undefined (reading 'createKeywordTypeNode')` at `openapi-typescript/dist/lib/ts.mjs:11`. TS 7 (native port) has no JS compiler API (`ts.factory` is undefined). `--legacy-peer-deps` only gets it installed; it does not make it run. |
| 6.0.3 | OK | OK | OK | OK |

- Pin **typescript 6.0.3** (newest 6.x; 6.0.x is also inside typescript-eslint's `<6.1.0`). 6.x is still the JS implementation, so `ts.factory` exists.
- Peer conflict: openapi-typescript declares `typescript ^5.x`, so plain `npm i` fails with ERESOLVE even on 6.0.3. Fix without `--legacy-peer-deps` (used here, `npm i` and `npm ci` both work, and shadcn's own internal `npm install` works too): in `package.json`
  `"overrides": { "openapi-typescript": { "typescript": "$typescript" } }`.
  Tried and failed: overriding with `"npm:typescript@6.0.3"` to keep TS 7 for tsc and 6 for openapi-typescript (ERESOLVE / invalid tree). Not pursued further.
- Revisit TS 7 when openapi-typescript ships a TS-7-compatible release. TS 7 works for the rest of the toolchain (tsc -b, vite, vitest), so only the type generator blocks it. Alternative to keep TS 7: generate the types in CI/dev with a separate tool (not tested, NOT VERIFIED).
- TS 6 gotcha: `baseUrl` is deprecated (TS5101 error unless `ignoreDeprecations: "6.0"`). Drop `baseUrl`; `paths` with `./src/*` works under `moduleResolution: bundler`. (TS 7 accepts the same config.)
- ESLint: `eslint 10.12.0` + `typescript-eslint 8.71.2` + `@eslint/js` installed with no peer error on TS 6.0.3 and `eslint src` exited 0 with a flat config of `js.configs.recommended` + `tseslint.configs.recommended`. I removed it again to keep the spike clean (not in package.json). With TS 7 typescript-eslint is out of range (`<6.1.0`): NOT VERIFIED whether it works there.

## Q2. Scaffold files
`admin-ui/` files, in full:

### package.json
```json
{
  "name": "admin-ui",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "test": "vitest run",
    "gen:api": "openapi-typescript openapi.json -o src/api/schema.d.ts"
  },
  "dependencies": {
    "@fontsource-variable/geist": "^5.3.0",
    "@hookform/resolvers": "^5.9.1",
    "@tanstack/react-query": "^5.104.2",
    "@tanstack/react-table": "^9.3.1",
    "class-variance-authority": "^0.7.1",
    "cn": "^0.4.0",
    "lucide-react": "^1.56.0",
    "next-themes": "^0.4.6",
    "openapi-fetch": "^0.17.0",
    "radix-ui": "^1.8.1",
    "react": "^19.3.0",
    "react-dom": "^19.3.0",
    "react-hook-form": "^7.90.0",
    "react-router": "^8.4.0",
    "shadcn": "^4.21.4",
    "sonner": "^2.0.8",
    "tw-animate-css": "^1.4.0",
    "zod": "^4.6.7"
  },
  "devDependencies": {
    "@tailwindcss/vite": "^4.3.3",
    "@testing-library/jest-dom": "^7.0.1",
    "@testing-library/react": "^16.3.3",
    "@testing-library/user-event": "^14.6.8",
    "@types/node": "^26.6.5",
    "@types/react": "^19.3.0",
    "@types/react-dom": "^19.3.0",
    "@vitejs/plugin-react": "^6.1.2",
    "jsdom": "^30.1.2",
    "msw": "^3.0.3",
    "openapi-typescript": "^7.13.0",
    "tailwindcss": "^4.3.3",
    "typescript": "^6.0.3",
    "vite": "^8.3.4",
    "vitest": "^5.0.4"
  },
  "overrides": {
    "openapi-typescript": {
      "typescript": "$typescript"
    }
  }
}
```

### vite.config.ts
```
/// <reference types="vitest/config" />
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  base: '/admin/',
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  build: {
    outDir: '../out/wwwroot/admin',
    emptyOutDir: true,
  },
  server: {
    proxy: {
      '/admin/api': 'http://localhost:5080',
      '/admin/jobs': 'http://localhost:5080',
    },
  },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    css: false,
  },
})
```

### tsconfig.json
```
{
  "files": [],
  "references": [{ "path": "./tsconfig.app.json" }, { "path": "./tsconfig.node.json" }],
  "compilerOptions": {
    "paths": { "@/*": ["./src/*"] }
  }
}
```

### tsconfig.app.json
```
{
  "compilerOptions": {
    "tsBuildInfoFile": "./node_modules/.tmp/tsconfig.app.tsbuildinfo",
    "target": "ES2023",
    "lib": ["ES2023", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "types": ["vite/client", "vitest/globals", "@testing-library/jest-dom"],
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "verbatimModuleSyntax": true,
    "isolatedModules": true,
    "skipLibCheck": true,
    "noEmit": true,
    "paths": { "@/*": ["./src/*"] }
  },
  "include": ["src"]
}
```

### tsconfig.node.json
```
{
  "compilerOptions": {
    "tsBuildInfoFile": "./node_modules/.tmp/tsconfig.node.tsbuildinfo",
    "target": "ES2023",
    "lib": ["ES2023"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "types": ["node"],
    "strict": true,
    "verbatimModuleSyntax": true,
    "isolatedModules": true,
    "skipLibCheck": true,
    "noEmit": true
  },
  "include": ["vite.config.ts"]
}
```

### index.html
```
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>ExtraSpace Admin</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

### src/main.tsx
```
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { QueryClientProvider } from '@tanstack/react-query'
import { RouterProvider } from 'react-router/dom'
import { makeQueryClient } from '@/lib/query'
import { router } from '@/router'
import './index.css'

const queryClient = makeQueryClient()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={router} />
    </QueryClientProvider>
  </StrictMode>,
)
```

### src/index.css
(129 lines, written by shadcn init; path: admin-ui/src/index.css). Before shadcn it was one line: `@import "tailwindcss";`. Head:
```css
@import "tailwindcss";
@import "tw-animate-css";
@import "shadcn/tailwind.css";
@import "@fontsource-variable/geist";

@custom-variant dark (&:is(.dark *));

@theme inline {
```

Notes: `outDir: '../out/wwwroot/admin'` with `emptyOutDir: true` worked with no warning or prompt (Vite 8 empties it because it is explicit). Built `index.html` references `/admin/assets/...`. Dev proxy keys are plain prefixes. The `@` alias is needed in THREE places: `vite.config.ts`, `tsconfig.app.json` paths, and the ROOT `tsconfig.json` paths (shadcn reads only the root file; see gotchas).

## Q3. Tailwind 4 + shadcn
Tailwind 4 needs no config file: `@tailwindcss/vite` plugin + `@import "tailwindcss";` in the CSS.

Exact non-interactive commands (run in `admin-ui/`, after the `@` alias exists in the root `tsconfig.json`, and with the `overrides` above):
```
npx shadcn@4.21.4 init -t vite -b radix -p nova -y --no-reinstall --no-monorepo --no-rtl --no-pointer
npx shadcn@4.21.4 add button input label dialog table select checkbox badge dropdown-menu sonner -y -o
```
- `init` without `-p nova` stops at a "Which preset" prompt; without `--no-reinstall` it stops if `components.json` exists ("re-install existing components?"); `-f` is needed to re-run over an existing `components.json`. `-d` defaults to the `next` template, so do not use it.
- Needs network: it contacts the shadcn registry (`ui.shadcn.com`, "Checking registry") and runs `npm install` for the new deps.
- Files written by `init`: `components.json` (style `radix-nova`, baseColor neutral, cssVariables, iconLibrary lucide, aliases `@/components`, `@/lib/utils`, `@/components/ui`, `@/lib`, `@/hooks`), `src/index.css` (changed: adds `@import "tw-animate-css"; @import "shadcn/tailwind.css"; @import "@fontsource-variable/geist";`, `@custom-variant dark`, `@theme inline` tokens, `:root` and `.dark` oklch variables, `@layer base`), `src/lib/utils.ts` (`export { cn } from "cn"`), `src/components/ui/button.tsx`, and `package.json` + lockfile (deps listed above).
- Files written by `add`: `src/components/ui/{input,label,table,select,checkbox,badge,dropdown-menu,sonner,dialog}.tsx` (it skipped the existing `button.tsx`; `-o` overwrites). It added deps `sonner`, `next-themes` (sonner.tsx uses `useTheme` from next-themes; fine in plain Vite, there is no provider so theme is "system"). `index.css` unchanged by `add`.
- Compiles under TS 6.0.3 (`tsc -b` exit 0, strict + noUnused*). Under TS 7.0.2 also exit 0. lucide-react 1.56 icon names used by sonner.tsx (`CircleCheckIcon`, `InfoIcon`, `TriangleAlertIcon`, `OctagonXIcon`, `Loader2Icon`) compile.
- Component files import from `"cn"`, `"radix-ui"` (`import { Slot } from "radix-ui"`) and `class-variance-authority`.

## Q4. Smoke app
Files (all under `admin-ui/`): `src/router.tsx`, `src/main.tsx`, `src/api/client.ts`, `src/lib/query.ts`, `src/pages/{Layout,DashboardPage,StaffPage}.tsx`, `src/pages/{Dashboard,StaffPage}.test.tsx`, `src/test/{setup,server,relative-fetch}.ts`, `openapi.json`, `src/api/schema.d.ts` (generated).

### src/router.tsx
```
import { createBrowserRouter } from 'react-router'
import { Layout } from '@/pages/Layout'
import { DashboardPage } from '@/pages/DashboardPage'
import { StaffPage } from '@/pages/StaffPage'

export const routes = [
  {
    path: '/',
    Component: Layout,
    children: [
      { index: true, Component: DashboardPage },
      { path: 'staff', Component: StaffPage },
    ],
  },
]

export const router = createBrowserRouter(routes, { basename: '/admin' })
```

### src/api/client.ts
```
import createClient, { type Middleware } from 'openapi-fetch'
import type { paths } from './schema'

export const csrfMiddleware: Middleware = {
  onRequest({ request }) {
    if (request.method === 'POST') {
      request.headers.set('X-CSRF-TOKEN', 'csrf-from-cookie')
    }
    return request
  },
}

export function createUnauthorizedMiddleware(onUnauthorized: () => void): Middleware {
  return {
    onResponse({ response }) {
      if (response.status === 401) onUnauthorized()
      return response
    },
  }
}

export const api = createClient<paths>({
  baseUrl: '/',
  // Look fetch up at call time: openapi-fetch otherwise keeps the fetch that existed at import,
  // which MSW (patched in beforeAll) would never see.
  fetch: (request) => globalThis.fetch(request),
})
api.use(csrfMiddleware)
api.use(createUnauthorizedMiddleware(() => console.warn('401: redirect to sign-in')))
```

### src/pages/Layout.tsx
```
import { NavLink, Outlet } from 'react-router'
import { Toaster } from '@/components/ui/sonner'

const link = ({ isActive }: { isActive: boolean }) =>
  isActive ? 'font-bold underline' : 'text-muted-foreground'

export function Layout() {
  return (
    <div className="p-4">
      <nav className="flex gap-4">
        <NavLink to="/" end className={link}>Dashboard</NavLink>
        <NavLink to="/staff" className={link}>Staff</NavLink>
      </nav>
      <main className="mt-4"><Outlet /></main>
      <Toaster />
    </div>
  )
}
```

### src/pages/DashboardPage.tsx
```
import { useQuery } from '@tanstack/react-query'
import { createColumnHelper, tableFeatures, useTable } from '@tanstack/react-table'
import { api } from '@/api/client'
import { Badge } from '@/components/ui/badge'
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table'

type Row = { site: string; units: number; status: string }

const features = tableFeatures({})
const helper = createColumnHelper<typeof features, Row>()
const columns = helper.columns([
  helper.accessor('site', { header: 'Site' }),
  helper.accessor('units', { header: 'Units' }),
  helper.accessor('status', { header: 'Status', cell: (c) => <Badge>{c.getValue()}</Badge> }),
])
const rows: Row[] = [
  { site: 'Tai Seng', units: 120, status: 'Open' },
  { site: 'Kuala Lumpur', units: 80, status: 'Open' },
]

export function DashboardPage() {
  const me = useQuery({
    queryKey: ['me'],
    queryFn: async () => {
      const { data, error } = await api.GET('/admin/api/staff/me')
      if (error) throw error
      return data
    },
  })
  const table = useTable({ features, columns, data: rows })

  return (
    <div>
      <h1 className="text-xl">Dashboard</h1>
      <p data-testid="me">{me.isPending ? 'Loading' : me.data ? `Me: ${me.data.id} v${me.data.version}` : 'Error'}</p>
      <Table>
        <TableHeader>
          {table.getHeaderGroups().map((g) => (
            <TableRow key={g.id}>
              {g.headers.map((h) => (
                <TableHead key={h.id}>{h.isPlaceholder ? null : <table.FlexRender header={h} />}</TableHead>
              ))}
            </TableRow>
          ))}
        </TableHeader>
        <TableBody>
          {table.getRowModel().rows.map((r) => (
            <TableRow key={r.id}>
              {r.getAllCells().map((c) => (
                <TableCell key={c.id}><table.FlexRender cell={c} /></TableCell>
              ))}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  )
}
```

### src/pages/StaffPage.tsx
```
import { useMutation } from '@tanstack/react-query'
import { zodResolver } from '@hookform/resolvers/zod'
import { useForm } from 'react-hook-form'
import { toast } from 'sonner'
import { z } from 'zod'
import { api } from '@/api/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

const schema = z.object({
  email: z.email('Enter a valid email'),
  name: z.string().min(1, 'Name is required'),
})
type FormValues = z.infer<typeof schema>

export function StaffPage() {
  const form = useForm<FormValues>({ resolver: zodResolver(schema), defaultValues: { email: '', name: '' } })
  const create = useMutation({
    mutationFn: async (body: FormValues) => {
      const { data, error } = await api.POST('/admin/api/staff', { body })
      if (error) throw error
      return data
    },
    onSuccess: () => toast.success('Staff created'),
  })
  const { errors } = form.formState

  return (
    <form onSubmit={form.handleSubmit((v) => create.mutate(v))} className="grid max-w-sm gap-3">
      <Label htmlFor="email">Email</Label>
      <Input id="email" {...form.register('email')} />
      {errors.email && <p role="alert">{errors.email.message}</p>}
      <Label htmlFor="name">Name</Label>
      <Input id="name" {...form.register('name')} />
      {errors.name && <p role="alert">{errors.name.message}</p>}
      <Button type="submit" disabled={create.isPending}>Create</Button>
      {create.isSuccess && <p data-testid="created">Created {create.data?.id}</p>}
    </form>
  )
}
```

### src/test/setup.ts
```
import './relative-fetch'
import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/react'
import { afterAll, afterEach, beforeAll } from 'vitest'
import { server } from './server'

// jsdom has no matchMedia (sonner and next-themes call it)
if (!window.matchMedia) {
  window.matchMedia = (query: string) =>
    ({
      matches: false,
      media: query,
      onchange: null,
      addEventListener: () => {},
      removeEventListener: () => {},
      addListener: () => {},
      removeListener: () => {},
      dispatchEvent: () => false,
    }) as MediaQueryList
}

beforeAll(() => server.listen({ onUnhandledFrame: 'error' }))
afterEach(() => {
  server.resetHandlers()
  cleanup()
})
afterAll(() => server.close())
```

### src/test/server.ts
```
import { setupServer } from 'msw/node'

export const server = setupServer()
```

### src/test/relative-fetch.ts
```
// Node's Request/fetch only accept absolute URLs, but jsdom has a base URL
// (location.href). Resolve relative URLs against it so `new Request('/x')`
// (what openapi-fetch does with baseUrl '/') works in tests like in a browser.
const NativeRequest = globalThis.Request

class RelativeRequest extends NativeRequest {
  constructor(input: RequestInfo | URL, init?: RequestInit) {
    super(typeof input === 'string' ? new URL(input, globalThis.location.href).href : input, init)
  }
}

globalThis.Request = RelativeRequest as typeof Request
```

### src/pages/StaffPage.test.tsx
```
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClientProvider } from '@tanstack/react-query'
import { http, HttpResponse } from 'msw'
import { MemoryRouter } from 'react-router'
import { makeQueryClient } from '@/lib/query'
import { StaffPage } from '@/pages/StaffPage'
import { server } from '@/test/server'

function renderPage() {
  return render(
    <QueryClientProvider client={makeQueryClient()}>
      <MemoryRouter><StaffPage /></MemoryRouter>
    </QueryClientProvider>,
  )
}

describe('StaffPage', () => {
  it('shows validation errors and sends nothing when invalid', async () => {
    const user = userEvent.setup()
    renderPage()
    await user.type(screen.getByLabelText('Email'), 'nope')
    await user.click(screen.getByRole('button', { name: 'Create' }))
    expect(await screen.findByText('Enter a valid email')).toBeInTheDocument()
    expect(screen.getByText('Name is required')).toBeInTheDocument()
  })

  it('posts the body with the CSRF header', async () => {
    let body: unknown
    let csrf: string | null = null
    server.use(
      http.post('*/admin/api/staff', async ({ request }) => {
        body = await request.json()
        csrf = request.headers.get('X-CSRF-TOKEN')
        return HttpResponse.json({ id: '0191a2b3-0000-7000-8000-000000000001', version: 1 }, { status: 201 })
      }),
    )
    const user = userEvent.setup()
    renderPage()
    await user.type(screen.getByLabelText('Email'), 'a@b.com')
    await user.type(screen.getByLabelText('Name'), 'Ada')
    await user.click(screen.getByRole('button', { name: 'Create' }))
    expect(await screen.findByTestId('created')).toHaveTextContent('Created 0191a2b3')
    expect(body).toEqual({ email: 'a@b.com', name: 'Ada' })
    expect(csrf).toBe('csrf-from-cookie')
  })
})
```

### src/pages/Dashboard.test.tsx
```
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClientProvider } from '@tanstack/react-query'
import { http, HttpResponse } from 'msw'
import { RouterProvider } from 'react-router/dom'
import { createMemoryRouter } from 'react-router'
import { makeQueryClient } from '@/lib/query'
import { routes } from '@/router'
import { server } from '@/test/server'

function renderApp(path: string) {
  const router = createMemoryRouter(routes, { basename: '/admin', initialEntries: [path] })
  return render(
    <QueryClientProvider client={makeQueryClient()}>
      <RouterProvider router={router} />
    </QueryClientProvider>,
  )
}

describe('app routes', () => {
  it('renders the dashboard with data, the table, and navigates to Staff', async () => {
    server.use(
      http.get('*/admin/api/staff/me', () =>
        HttpResponse.json({ id: '0191a2b3-0000-7000-8000-000000000001', version: 4 }),
      ),
    )
    const user = userEvent.setup()
    renderApp('/admin/')
    expect(await screen.findByText(/v4/)).toBeInTheDocument()
    expect(screen.getByText('Tai Seng')).toBeInTheDocument()
    expect(screen.getByRole('columnheader', { name: 'Units' })).toBeInTheDocument()
    await user.click(screen.getByRole('link', { name: 'Staff' }))
    expect(await screen.findByLabelText('Email')).toBeInTheDocument()
  })

  it('runs the 401 middleware', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})
    server.use(
      http.get('*/admin/api/staff/me', () =>
        HttpResponse.json({ status: 401, code: 'UNAUTHORIZED' }, { status: 401 }),
      ),
    )
    renderApp('/admin/')
    expect(await screen.findByText('Error')).toBeInTheDocument()
    expect(warn).toHaveBeenCalledWith('401: redirect to sign-in')
  })
})
```

### openapi.json
```
{
  "openapi": "3.1.1",
  "info": { "title": "ExtraSpace", "version": "1.0" },
  "paths": {
    "/admin/api/staff/me": {
      "get": {
        "operationId": "getMe",
        "responses": {
          "200": { "description": "OK", "content": { "application/json": { "schema": { "$ref": "#/components/schemas/Me" } } } },
          "401": { "description": "Unauthorized", "content": { "application/problem+json": { "schema": { "$ref": "#/components/schemas/ProblemDetails" } } } }
        }
      }
    },
    "/admin/api/staff": {
      "post": {
        "operationId": "createStaff",
        "requestBody": { "required": true, "content": { "application/json": { "schema": { "$ref": "#/components/schemas/CreateStaff" } } } },
        "responses": {
          "201": { "description": "Created", "content": { "application/json": { "schema": { "$ref": "#/components/schemas/Me" } } } },
          "400": { "description": "Bad", "content": { "application/problem+json": { "schema": { "$ref": "#/components/schemas/ProblemDetails" } } } }
        }
      }
    }
  },
  "components": {
    "schemas": {
      "Me": {
        "type": "object",
        "required": ["id", "version"],
        "properties": {
          "id": { "type": "string", "format": "uuid" },
          "version": { "type": "integer", "format": "uint32" },
          "count": { "type": "integer", "format": "int32" },
          "mixed": { "type": ["integer", "string"], "format": "int32" },
          "note": { "type": ["string", "null"] }
        }
      },
      "CreateStaff": {
        "type": "object",
        "required": ["email", "name"],
        "properties": { "email": { "type": "string", "format": "email" }, "name": { "type": "string" } }
      },
      "ProblemDetails": {
        "type": "object",
        "properties": {
          "type": { "type": ["string", "null"] },
          "title": { "type": ["string", "null"] },
          "status": { "type": ["integer", "string", "null"], "format": "int32" },
          "detail": { "type": ["string", "null"] },
          "code": { "type": ["string", "null"] },
          "traceId": { "type": ["string", "null"] },
          "errors": { "type": ["object", "null"], "additionalProperties": { "type": "array", "items": { "type": "string" } } }
        }
      }
    }
  }
}
```

(`src/lib/query.ts` and `src/main.tsx` are above/trivial: `makeQueryClient()` = `new QueryClient({ defaultOptions: { queries: { retry: false, refetchOnWindowFocus: false } } })`.)

Vitest config lives inside `vite.config.ts` (`test:` block, shown above): `globals: true`, `environment: 'jsdom'`, `setupFiles`, `css: false`. `types` in `tsconfig.app.json` include `vitest/globals` and `@testing-library/jest-dom`.

### Generated types (command: `npx openapi-typescript openapi.json -o src/api/schema.d.ts`, = `npm run gen:api`)
- `type: integer, format: uint32` -> `version: number` with a `/** Format: uint32 */` comment. `int32` -> `number` likewise. Neither becomes a branded or bigint type; there is no int64 handling here (not tested).
- `type: ["integer","string"], format: int32` -> `mixed?: number | string;`
- `["string","null"]` -> `string | null`; a property not in `required` becomes optional `?`; `uuid` -> `string`.
- Error responses are keyed by status and media type: `401: { content: { "application/problem+json": components["schemas"]["ProblemDetails"] } }`. openapi-fetch exposes this as `error` (typed as the union of non-2xx bodies) with no extra work.
- `ProblemDetails.status` typed `["integer","string","null"]` (as .NET emits it) -> `number | string | null`.
Full output is in `admin-ui/src/api/schema.d.ts`.

### React Router 8.4 (answers)
- `createBrowserRouter`, `createMemoryRouter`, `NavLink`, `Outlet`, `MemoryRouter` all import from `"react-router"` (single package; `react-router-dom` is not needed).
- `RouterProvider`: import it from `"react-router/dom"` (the DOM entry; it wraps updates in `flushSync`). `react-router` itself also exports a `RouterProvider`, but the `/dom` one is the one for browsers. Used `react-router/dom` in `main.tsx` and in the test.
- `createBrowserRouter(routes, { basename: '/admin' })` works. Route objects use `Component: X` (capital C) with `children` and `index: true`; no JSX `<Route>` needed. Peer: react >= 19.2.7; Node >= 22.22.
- Tested: `createMemoryRouter(routes, { basename: '/admin', initialEntries: ['/admin/'] })` renders the layout and the dashboard; `NavLink to="/staff"` click goes to Staff (test passes).

### TanStack Table 9.3.1 (answers)
- `useReactTable` -> `useTable`; `getCoreRowModel()` is no longer passed for a core table; you declare `features = tableFeatures({})` (module scope, stable) and pass `{ features, columns, data }`. Extra features (sorting, filtering, pagination, ...) are registered in `tableFeatures()` and their row models after their prerequisites; not tested here.
- `createColumnHelper<typeof features, Row>()` takes features as the FIRST generic; `helper.columns([helper.accessor('site', { header: 'Site' }), ...])` (wrap in `helper.columns`).
- `flexRender(...)` still exists, but the new way is `<table.FlexRender header={h} />` / `<table.FlexRender cell={c} />`.
- Core-only tables render cells with `row.getAllCells()` (not `getVisibleCells()`, which needs the column-visibility feature).
- Keep `columns`, `features` and the data fallback at module scope or memoised (new array each render re-computes row models). `useTable` subscribes to all state by default.
- A `@tanstack/react-table/legacy` export (`useLegacyTable`) exists for gradual v8 migration. The package ships its own docs in `node_modules/@tanstack/react-table/skills/*/SKILL.md`; read `migrate-v8-to-v9` before porting any table.

### React Hook Form + Zod 4 + resolvers 5.9.1
- `import { zodResolver } from '@hookform/resolvers/zod'` works with zod 4.6.7 and `useForm<z.infer<typeof schema>>({ resolver: zodResolver(schema) })` type-checks with no cast (all fields are plain strings; if a schema uses transform/coerce/default, use `useForm<z.input<S>, unknown, z.output<S>>` - NOT VERIFIED here).
- Zod 4: top-level `z.email('message')` (not `z.string().email()`, which is deprecated). `z.string().min(1, 'Name is required')` fine.
- Test shows both messages render on a bad submit.

### openapi-fetch 0.17.0
- `createClient<paths>({ baseUrl: '/' })`; `api.GET('/admin/api/staff/me')` gives `{ data, error, response }`; `api.POST('/admin/api/staff', { body })` body is type-checked against `CreateStaff`.
- Middleware: `api.use({ onRequest({ request }) { request.headers.set('X-CSRF-TOKEN', ...); return request }, onResponse({ response }) { if (response.status === 401) ...; return response } })`. Both worked: the POST test asserts the header; the 401 test asserts the callback ran. Type is `Middleware` (named export). Returning nothing/undefined passes the request through unchanged.
- openapi-fetch captures `globalThis.fetch` when `createClient` runs (at module import). MSW patches fetch later in `beforeAll`, so interception silently missed (real connection attempt -> "fetch failed"). Fix used: `fetch: (request) => globalThis.fetch(request)` in `createClient`. Harmless in production.

### MSW 3.0.3 (answers) vs MSW 2
- Same: `import { http, HttpResponse } from 'msw'`, `import { setupServer } from 'msw/node'`, handler syntax `http.post('*/admin/api/staff', async ({ request }) => HttpResponse.json(..., { status: 201 }))`, `server.use`, `server.resetHandlers`, `server.close`.
- Changed: the `server.listen` option `onUnhandledRequest` is now `onUnhandledFrame` (`'error' | 'warn' | 'bypass'` or a function). The old name is a type error under `tsc` and, at runtime, silently ignored (unhandled requests only warn). Easy to miss: vitest alone does not catch it, `tsc -b` does.
- Pattern `'*/admin/api/staff'` matched the absolute URL produced after the Request polyfill. MSW 3 declares `typescript >=5.9.x` as an optional peer; fine with 6.0.3.

### jsdom 30 gaps and how they were solved
1. Relative-URL fetch. Node's `Request`/`fetch` reject relative URLs (`TypeError: Failed to parse URL from /admin/api/staff/me`) because Node has no base URL, while jsdom has one (`location.href` = `http://localhost:3000/`). openapi-fetch builds `new Request(baseUrl + path)` with `baseUrl: '/'`. Fix: `src/test/relative-fetch.ts` replaces `globalThis.Request` with a subclass that resolves string inputs against `globalThis.location.href`; imported FIRST in `setup.ts`. Verified necessary: removing it makes the POST test fail. Alternative (not used): create the client with `baseUrl: location.origin` in tests, but the singleton client in the app would then need injecting.
2. `window.matchMedia` is missing (sonner's Toaster, rendered by the Layout, crashes with "window.matchMedia is not a function" and React Router's error boundary shows it). Stubbed in `setup.ts`.
3. `cleanup()` from RTL is called in `afterEach` explicitly because vitest `globals` is on but RTL's auto-cleanup relies on a global `afterEach`... (kept explicit to be safe; not checked whether it is redundant).
No `ResizeObserver` or `scrollIntoView` polyfill was needed for what was rendered. The Dialog, Select and DropdownMenu components were compiled but NOT rendered in tests, so their jsdom needs (pointer capture, ResizeObserver, scrollIntoView) are NOT VERIFIED.

## Q5. Gotchas (in the order hit)
1. `npm i` ERESOLVE: openapi-typescript peer `typescript ^5.x`. Fix: `overrides` above (also needed so shadcn's internal install does not fail: it surfaced as "npm error ERESOLVE" with a hint to try an older shadcn).
2. openapi-typescript on TS 7.0.2 crashes (no `ts.factory`). Pin TS 6.0.3.
3. shadcn wrote files into a literal `./@/components/ui/...` folder because it resolves the `@/*` alias only from the ROOT `tsconfig.json`'s `compilerOptions.paths` (project-references root had none). Fix: add `compilerOptions.paths` to the root `tsconfig.json` too, then delete the stray `@/` folder, `components.json`, and re-run. (`cn` is a real dep of the nova preset, installed in both runs.)
4. shadcn `init` prompts: preset, overwrite components.json, re-install components. Flags in Q3.
5. TS 6: `baseUrl` is deprecated (TS5101). Remove it.
6. MSW 3: `onUnhandledRequest` -> `onUnhandledFrame` (tsc error TS2353).
7. openapi-fetch holds the early `fetch` (MSW miss) and jsdom lacks relative URLs / matchMedia (see Q4).
8. Vite 8 (rolldown): no problems with `@vitejs/plugin-react 6.1.2`, `@tailwindcss/vite`, aliases, or an `outDir` outside the root. Build prints the >500 kB chunk warning (575 kB, 180 kB gzip) because of radix + router + table in one chunk; the warning text now suggests `build.rolldownOptions.output.codeSplitting` instead of `manualChunks` (not tried).
9. React 19.3 types: `@types/react 19.3.0` compiled all shadcn and app code under strict with no changes. lucide-react 1.x icon names with the `Icon` suffix (`CircleCheckIcon`) compile.
10. npm 11.16 prints `allow-scripts` warnings (fsevents install script not approved). Harmless here; run `npm approve-scripts` if the team wants silence. NOT VERIFIED whether any dependency needs a script on Linux CI (esbuild/rolldown/@tailwindcss/oxide use prebuilt optional packages here).
11. Stray write: early in the spike one `cp package.json /tmp/x` landed in an existing empty dir `/tmp/x`; I deleted that file and the (empty) directory. Nothing else was written outside the spike dir.

## Commands run and results (final state, after `rm -rf node_modules && npm ci`)
```
$ npx tsc -v                  -> Version 6.0.3
$ npm run gen:api             -> openapi-typescript 7.13.0  openapi.json -> src/api/schema.d.ts [11ms]
$ npm run build   (tsc -b && vite build)
[plugin builtin:vite-reporter] 
(!) Some chunks are larger than 500 kB after minification. Consider:
- Using dynamic import() to code-split the application
- Use build.rolldownOptions.output.codeSplitting to improve chunking: https://rolldown.rs/reference/OutputOptions.codeSplitting
- Adjust chunk size limit for this warning via build.chunkSizeWarningLimit.
✓ built in 401ms
$ npm test   (vitest run)
 RUN  v5.0.4 /private/tmp/claude-501/-Users-waiyanmin-Projects-Extra-Space-Claude/d7e129a8-92bf-4bb8-a926-d44a85811631/scratchpad/s05-spike/admin-ui
 Test Files  2 passed (2)
      Tests  4 passed (4)
   Start at  18:39:41
   Duration  722ms (environment 38%, import 23%, tests 19%, setup 14%, transform 6%)
```

## Differs from the previous major (short)
- **TypeScript 7**: native compiler; tsc/vite/vitest fine but no JS compiler API (breaks openapi-typescript). 6.x: `baseUrl` deprecated.
- **React Router 8**: single `react-router` package; `RouterProvider` from `react-router/dom`; `Component:` route property.
- **Vite 8**: rolldown bundler; config unchanged for our needs; chunk-split hint names `rolldownOptions`.
- **TanStack Table 9**: `useTable` + `tableFeatures()` + `table.FlexRender`; no `getCoreRowModel`; feature-gated APIs.
- **Zod 4**: `z.email()`; resolvers 5 works without a cast.
- **MSW 3**: `onUnhandledFrame` replaces `onUnhandledRequest`; rest of the handler API as MSW 2.
- **shadcn 4.21**: presets (`-p nova`), `-b radix|base`; uses `cn` package and the single `radix-ui` package; `shadcn/tailwind.css` import; needs root-tsconfig alias.
- **Tailwind 4**: CSS-first (`@import "tailwindcss"`, `@theme inline`), no config file, Vite plugin.
- **openapi-fetch 0.17**: `Middleware` with `onRequest`/`onResponse` taking an object arg; fetch captured at `createClient`.
- **Vitest 5**: config `test:` block in `vite.config.ts` with `/// <reference types="vitest/config" />` worked as before.
