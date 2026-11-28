import { flexRender, getCoreRowModel, useReactTable, type ColumnDef } from '@tanstack/react-table'
import { ChevronLeft, ChevronRight } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'

/** Bảng phân trang phía server: chỉ hiển thị trang hiện tại, tổng số dòng do API trả. */
export function DataTable<T>({
  columns,
  data,
  loading,
  page,
  limit,
  total,
  onPage,
  onRowClick,
  empty = 'Không có dữ liệu.',
}: {
  columns: ColumnDef<T>[]
  data: T[] | undefined
  loading?: boolean
  page?: number
  limit?: number
  total?: number
  onPage?: (p: number) => void
  onRowClick?: (row: T) => void
  empty?: string
}) {
  const table = useReactTable({ data: data ?? [], columns, getCoreRowModel: getCoreRowModel(), manualPagination: true })
  const pages = total !== undefined && limit ? Math.max(1, Math.ceil(total / limit)) : 1

  return (
    <div className="rounded-lg border bg-card">
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            {table.getHeaderGroups().map((hg) => (
              <TableRow key={hg.id}>
                {hg.headers.map((h) => (
                  <TableHead key={h.id} className="whitespace-nowrap text-xs uppercase tracking-wide">
                    {flexRender(h.column.columnDef.header, h.getContext())}
                  </TableHead>
                ))}
              </TableRow>
            ))}
          </TableHeader>
          <TableBody>
            {loading &&
              Array.from({ length: 5 }, (_, i) => (
                <TableRow key={i}>
                  {columns.map((_, j) => (
                    <TableCell key={j}>
                      <Skeleton className="h-5 w-full" />
                    </TableCell>
                  ))}
                </TableRow>
              ))}
            {!loading && table.getRowModel().rows.length === 0 && (
              <TableRow>
                <TableCell colSpan={columns.length} className="h-24 text-center text-muted-foreground">
                  {empty}
                </TableCell>
              </TableRow>
            )}
            {!loading &&
              table.getRowModel().rows.map((row) => (
                <TableRow
                  key={row.id}
                  className={onRowClick ? 'cursor-pointer' : undefined}
                  onClick={onRowClick ? () => onRowClick(row.original) : undefined}
                >
                  {row.getVisibleCells().map((cell) => (
                    <TableCell key={cell.id}>{flexRender(cell.column.columnDef.cell, cell.getContext())}</TableCell>
                  ))}
                </TableRow>
              ))}
          </TableBody>
        </Table>
      </div>
      {onPage && page !== undefined && total !== undefined && (
        <div className="flex items-center justify-between gap-2 border-t px-3 py-2 text-sm text-muted-foreground">
          <span className="num">
            {total === 0 ? '0' : `${(page - 1) * limit! + 1}–${Math.min(page * limit!, total)}`} / {total}
          </span>
          <div className="flex items-center gap-1">
            <Button variant="ghost" size="icon" disabled={page <= 1} onClick={() => onPage(page - 1)} aria-label="Trang trước">
              <ChevronLeft />
            </Button>
            <span className="num px-1">
              {page}/{pages}
            </span>
            <Button variant="ghost" size="icon" disabled={page >= pages} onClick={() => onPage(page + 1)} aria-label="Trang sau">
              <ChevronRight />
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}
