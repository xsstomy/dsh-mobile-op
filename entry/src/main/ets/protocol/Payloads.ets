/**
 * Typed request payloads.
 *
 * ArkTS rejects anonymous object literals (`arkts-no-untyped-obj-literals`), so
 * every request body is a declared class serialized with JSON.stringify.
 */

export class TypePayload {
  type: string;

  constructor(type: string) {
    this.type = type;
  }
}

export class SessionPayload {
  type: string;
  sessionId: string;

  constructor(type: string, sessionId: string) {
    this.type = type;
    this.sessionId = sessionId;
  }
}

export class RenamePayload {
  type: string = 'session-rename';
  sessionId: string;
  title: string;

  constructor(sessionId: string, title: string) {
    this.sessionId = sessionId;
    this.title = title;
  }
}

export class HistoryPayload {
  type: string = 'history';
  sessionId: string;
  maxMessages: number;
  maxBytes: number;
  view: string;
  beforeSeq?: number;

  constructor(sessionId: string, beforeSeq?: number) {
    this.sessionId = sessionId;
    this.maxMessages = 60;
    this.maxBytes = 4 * 1024 * 1024;
    this.view = 'conversation';
    if (beforeSeq !== undefined) {
      this.beforeSeq = beforeSeq;
    }
  }
}

export class SessionCreatePayload {
  type: string = 'session-create';
  requestId: string;
  workspaceId?: string;

  constructor(requestId: string, workspaceId?: string) {
    this.requestId = requestId;
    if (workspaceId !== undefined && workspaceId.length > 0) {
      this.workspaceId = workspaceId;
    }
  }
}

export class MessagePayload {
  type: string = 'message';
  text: string;
  mode: string;
  clientTimeZone: string;
  sessionId?: string;
  workspaceId?: string;
  cwd?: string;
  images?: OutgoingImage[];

  constructor(text: string, mode: string, sessionId?: string, workspaceId?: string, images?: OutgoingImage[]) {
    this.text = text;
    this.mode = mode;
    this.clientTimeZone = 'Asia/Shanghai';
    if (sessionId !== undefined && sessionId.length > 0) {
      this.sessionId = sessionId;
    }
    if (workspaceId !== undefined && workspaceId.length > 0) {
      this.workspaceId = workspaceId;
    }
    if (images !== undefined && images.length > 0) {
      this.images = images;
    }
  }
}

/** One image inside `message.images` (standard Base64, no data-url prefix). */
export class OutgoingImage {
  mediaType: string;
  data: string;
  name: string;

  constructor(mediaType: string, data: string, name: string) {
    this.mediaType = mediaType;
    this.data = data;
    this.name = name;
  }
}

export class DirectoryListPayload {
  type: string = 'directories';
  path?: string;

  constructor(path?: string) {
    if (path !== undefined && path.length > 0) {
      this.path = path;
    }
  }
}

export class DirectoryCreatePayload {
  type: string = 'directory-create';
  path: string;
  name: string;

  constructor(path: string, name: string) {
    this.path = path;
    this.name = name;
  }
}

export class QueueUpdatePayload {
  type: string = 'queue-update';
  sessionId: string;
  itemId: string;
  action: string;
  text?: string;

  constructor(sessionId: string, itemId: string, action: string, text?: string) {
    this.sessionId = sessionId;
    this.itemId = itemId;
    this.action = action;
    if (text !== undefined) {
      this.text = text;
    }
  }
}

/** One answer inside a `question-answer` batch (field names are wire-exact). */
export class QuestionAnswerItem {
  id: string;
  selected: string[];
  custom?: string;

  constructor(id: string, selected: string[], custom?: string) {
    this.id = id;
    this.selected = selected;
    const trimmed = custom === undefined ? '' : custom.replace(/^\s+|\s+$/g, '');
    if (trimmed.length > 0) {
      this.custom = trimmed;
    }
  }
}

export class QuestionAnswerPayload {
  type: string = 'question-answer';
  rpcId: string;
  sessionId: string;
  answers: QuestionAnswerItem[];

  constructor(rpcId: string, sessionId: string, answers: QuestionAnswerItem[]) {
    this.rpcId = rpcId;
    this.sessionId = sessionId;
    this.answers = answers;
  }
}

export class QuestionCancelPayload {
  type: string = 'question-cancel';
  rpcId: string;
  sessionId: string;

  constructor(rpcId: string, sessionId: string) {
    this.rpcId = rpcId;
    this.sessionId = sessionId;
  }
}

export class ApprovalResponsePayload {
  type: string = 'approval-response';
  rpcId: string;
  sessionId: string;
  approvalId: string;
  outcome: string;

  constructor(rpcId: string, sessionId: string, approvalId: string, outcome: string) {
    this.rpcId = rpcId;
    this.sessionId = sessionId;
    this.approvalId = approvalId;
    this.outcome = outcome;
  }
}

/** Compare-and-set reference required by every goal mutation. */
export class GoalRef {
  id: string;
  revision: number;

  constructor(id: string, revision: number) {
    this.id = id;
    this.revision = revision;
  }
}

export class GoalMutationPayload {
  type: string;
  sessionId: string;
  ref: GoalRef;
  objective?: string;
  maxGoalRounds?: number;

  constructor(type: string, sessionId: string, ref: GoalRef, objective?: string, maxGoalRounds?: number) {
    this.type = type;
    this.sessionId = sessionId;
    this.ref = ref;
    if (objective !== undefined && objective.replace(/^\s+|\s+$/g, '').length > 0) {
      this.objective = objective;
    }
    if (maxGoalRounds !== undefined && maxGoalRounds > 0) {
      this.maxGoalRounds = maxGoalRounds;
    }
  }
}

export class SelectModelPayload {
  type: string = 'select-model';
  sessionId: string;
  provider: string;
  model: string;
  reasoningEffort?: string;

  constructor(sessionId: string, provider: string, model: string, reasoningEffort?: string) {
    this.sessionId = sessionId;
    this.provider = provider;
    this.model = model;
    if (reasoningEffort !== undefined && reasoningEffort.length > 0) {
      this.reasoningEffort = reasoningEffort;
    }
  }
}

export class PermissionPayload {
  type: string = 'permission';
  sessionId: string;
  name: string;

  constructor(sessionId: string, name: string) {
    this.sessionId = sessionId;
    this.name = name;
  }
}

export class SetDefaultPayload {
  type: string = 'set-default';
  target: string;
  value: string;

  constructor(target: string, value: string) {
    this.target = target;
    this.value = value;
  }
}

export class SaveDefaultModelPayload {
  type: string = 'save-default-model';
  provider: string;
  model: string;
  reasoningEffort?: string;

  constructor(provider: string, model: string, reasoningEffort?: string) {
    this.provider = provider;
    this.model = model;
    if (reasoningEffort !== undefined && reasoningEffort.length > 0) {
      this.reasoningEffort = reasoningEffort;
    }
  }
}

export class CommandExecutePayload {
  type: string = 'command-execute';
  sessionId: string;
  line: string;
  images: string[] = [];

  constructor(sessionId: string, line: string) {
    this.sessionId = sessionId;
    this.line = line;
  }
}

export class CommandQueryPayload {
  type: string;
  sessionId: string;
  command: string;

  constructor(type: string, sessionId: string, command: string) {
    this.type = type;
    this.sessionId = sessionId;
    this.command = command;
  }
}

export class CommandSelectPayload {
  type: string = 'command-select';
  sessionId: string;
  command: string;
  optionId: string;

  constructor(sessionId: string, command: string, optionId: string) {
    this.sessionId = sessionId;
    this.command = command;
    this.optionId = optionId;
  }
}

export class CommandsQueryPayload {
  type: string = 'commands';
  sessionId: string;
  locale: string;

  constructor(sessionId: string, locale: string) {
    this.sessionId = sessionId;
    this.locale = locale;
  }
}

/** Full (untrimmed) history for the trajectory page: no `view` field on purpose. */
export class TrajectoryPayload {
  type: string = 'history';
  sessionId: string;
  maxMessages: number;
  maxBytes: number;

  constructor(sessionId: string, maxMessages: number, maxBytes: number) {
    this.sessionId = sessionId;
    this.maxMessages = maxMessages;
    this.maxBytes = maxBytes;
  }
}

export class WorkspaceCreatePayload {
  type: string = 'workspace-create';
  path: string;

  constructor(path: string) {
    this.path = path;
  }
}

export class FileListPayload {
  type: string = 'file-list';
  sessionId: string;
  requestId: string;
  path?: string;

  constructor(sessionId: string, requestId: string, path?: string) {
    this.sessionId = sessionId;
    this.requestId = requestId;
    if (path !== undefined && path.length > 0) {
      this.path = path;
    }
  }
}

export class FileDownloadOpenPayload {
  type: string = 'file-download-open';
  requestId: string;
  sessionId: string;
  path: string;

  constructor(requestId: string, sessionId: string, path: string) {
    this.requestId = requestId;
    this.sessionId = sessionId;
    this.path = path;
  }
}

export class FileDownloadReadPayload {
  type: string = 'file-download-read';
  transferId: string;
  offset: number;

  constructor(transferId: string, offset: number) {
    this.transferId = transferId;
    this.offset = offset;
  }
}

export class FileDownloadCancelPayload {
  type: string = 'file-download-cancel';
  transferId: string;

  constructor(transferId: string) {
    this.transferId = transferId;
  }
}

export class AttachmentPayload {
  type: string = 'attachment';
  sessionId: string;
  attachmentId: string;

  constructor(sessionId: string, attachmentId: string) {
    this.sessionId = sessionId;
    this.attachmentId = attachmentId;
  }
}

/** Host session search (query only; the reply carries `items`). */
export class SearchPayload {
  type: string = 'search';
  query: string;

  constructor(query: string) {
    this.query = query;
  }
}
