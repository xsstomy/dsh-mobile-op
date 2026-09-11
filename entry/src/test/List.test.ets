import conversationTest from './Conversation.test';
import filesTest from './Files.test';
import formatTest from './Format.test';
import gatewayFramesTest from './GatewayFrames.test';
import historyTest from './History.test';
import imagesTest from './Images.test';
import mentionsTest from './Mentions.test';
import pairingTest from './PairingPayload.test';
import protocolTest from './Protocol.test';
import questionsTest from './Questions.test';
import queueTest from './Queue.test';
import requestTrackerTest from './RequestTracker.test';
import settingsTest from './Settings.test';
import statsTest from './Stats.test';
import statusLineTest from './StatusLine.test';
import todosTest from './Todos.test';
import trajectoryTest from './Trajectory.test';
import turnActivityTest from './TurnActivity.test';

export default function testsuite(): void {
  protocolTest();
  questionsTest();
  queueTest();
  pairingTest();
  requestTrackerTest();
  settingsTest();
  statsTest();
  statusLineTest();
  todosTest();
  trajectoryTest();
  historyTest();
  imagesTest();
  mentionsTest();
  conversationTest();
  turnActivityTest();
  formatTest();
  filesTest();
  gatewayFramesTest();
}
