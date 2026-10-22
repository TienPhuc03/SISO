import {
  WebSocketGateway,
  WebSocketServer,
  OnGatewayConnection,
  OnGatewayDisconnect,
  SubscribeMessage,
  MessageBody,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { Logger } from '@nestjs/common';

@WebSocketGateway({
  cors: {
    origin: '*',
  },
  namespace: '/turf-ws',
})
export class TurfGateway implements OnGatewayConnection, OnGatewayDisconnect {
  private readonly logger = new Logger(TurfGateway.name);

  @WebSocketServer()
  server: Server;

  handleConnection(client: Socket) {
    this.logger.log(`Client kết nối WebSocket: ${client.id}`);
  }

  handleDisconnect(client: Socket) {
    this.logger.log(`Client ngắt kết nối WebSocket: ${client.id}`);
  }

  /**
   * Phát sự kiện đổi màu các ô lục giác H3 tới toàn bộ ứng dụng sinh viên
   */
  broadcastHexClaimed(payload: {
    universityId: string;
    universityCode: string;
    hexColor: string;
    claimedHexes: string[];
    claimedBy: string;
  }) {
    this.logger.log(
      `[Broadcast] Trường ${payload.universityCode} đã chiếm ${payload.claimedHexes.length} ô lục giác!`,
    );
    this.server.emit('hex_claimed', payload);
  }

  @SubscribeMessage('ping')
  handlePing(@MessageBody() data: string): string {
    return 'pong';
  }
}
