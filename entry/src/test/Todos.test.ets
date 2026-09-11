import { describe, expect, it } from '@ohos/hypium';
import { TodoRow, shouldApplyTodos, todoProgressLabel, todoProgressOf, todoRowsOf } from '../main/ets/sync/Todos';

export default function todosTest(): void {
  describe('todos', () => {
    it('maps the wire todo array and defaults missing fields', 0, () => {
      const rows = todoRowsOf([{ content: '构建 APK' }, { status: 'completed' }]);
      expect(rows !== null).assertTrue();
      const list: TodoRow[] = rows ?? [];
      expect(list.length).assertEqual(2);
      expect(list[0].content).assertEqual('构建 APK');
      expect(list[0].status).assertEqual('pending');
      expect(list[1].content).assertEqual('');
      expect(list[1].status).assertEqual('completed');
    });

    it('keeps the never-written null distinct from an empty list', 0, () => {
      expect(todoRowsOf(null) === null).assertTrue();
      expect(todoRowsOf(undefined) === null).assertTrue();
      const empty: TodoRow[] | null = todoRowsOf([]);
      expect(empty === null).assertFalse();
      expect(todoProgressOf(empty).total).assertEqual(0);
    });

    it('counts completed / in-progress / pending', 0, () => {
      const rows = todoRowsOf([
        { content: 'a', status: 'completed' },
        { content: 'b', status: 'in_progress' },
        { content: 'c', status: 'pending' },
        { content: 'd', status: 'pending' }
      ]);
      const progress = todoProgressOf(rows);
      expect(progress.done).assertEqual(1);
      expect(progress.active).assertEqual(1);
      expect(progress.pending).assertEqual(2);
      expect(progress.total).assertEqual(4);
    });

    it('labels the header like the WebUI and drops zero segments', 0, () => {
      const label = todoProgressLabel({ done: 0, active: 1, pending: 7, total: 8 });
      expect(label.indexOf('1 进行中') >= 0).assertTrue();
      expect(label.indexOf('7 待处理') > label.indexOf('1 进行中')).assertTrue();
      expect(label.indexOf('已完成') < 0).assertTrue();
      const all = todoProgressLabel({ done: 2, active: 1, pending: 3, total: 6 });
      expect(all.indexOf('2 已完成') >= 0).assertTrue();
      expect(all.indexOf('3 待处理') >= 0).assertTrue();
    });

    it('renders an empty label when there is nothing to count', 0, () => {
      expect(todoProgressLabel(todoProgressOf(null))).assertEqual('');
    });

    it('drops frames older than the applied asOfSeq', 0, () => {
      expect(shouldApplyTodos(43, 42)).assertTrue();
      expect(shouldApplyTodos(42, 42)).assertTrue();
      expect(shouldApplyTodos(41, 42)).assertFalse();
      expect(shouldApplyTodos(undefined, 42)).assertTrue();
      expect(shouldApplyTodos(0, -1)).assertTrue();
    });
  });
}