import { Navigate, Route, Routes } from 'react-router-dom'
import { Loader2 } from 'lucide-react'
import { AppShell } from '@/components/layout/AppShell'
import { LoginPage } from '@/pages/LoginPage'
import { useAuth } from '@/lib/auth'
import { AntiCheatPage } from '@/features/anti-cheat/AntiCheatPage'
import { SessionDetailPage } from '@/features/anti-cheat/SessionDetailPage'
import { TerritoryMapPage } from '@/features/territory/TerritoryMapPage'
import { OverviewPage } from '@/features/overview/OverviewPage'
import { SeasonsPage } from '@/features/catalog/SeasonsPage'
import { StudentsPage } from '@/features/students/StudentsPage'
import { StudentDetailPage } from '@/features/students/StudentDetailPage'
import { ActionsPage } from '@/features/actions/ActionsPage'
import { ForumReportsPage } from '@/features/forum/ForumReportsPage'

function RequireAdmin({ children }: { children: React.ReactNode }) {
  const { status } = useAuth()
  if (status === 'loading')
    return (
      <div className="grid min-h-dvh place-items-center" role="status" aria-label="Đang tải">
        <Loader2 className="size-6 animate-spin text-muted-foreground" />
      </div>
    )
  if (status !== 'admin') return <Navigate to="/login" replace />
  return <>{children}</>
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route
        element={
          <RequireAdmin>
            <AppShell />
          </RequireAdmin>
        }
      >
        <Route index element={<Navigate to="/anti-cheat" replace />} />
        <Route path="anti-cheat" element={<AntiCheatPage />} />
        <Route path="sessions/:id" element={<SessionDetailPage />} />
        <Route path="map" element={<TerritoryMapPage />} />
        <Route path="overview" element={<OverviewPage />} />
        <Route path="seasons" element={<SeasonsPage />} />
        <Route path="students" element={<StudentsPage />} />
        <Route path="students/:id" element={<StudentDetailPage />} />
        <Route path="actions" element={<ActionsPage />} />
        <Route path="forum" element={<ForumReportsPage />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  )
}
