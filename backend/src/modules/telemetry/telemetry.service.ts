import { Injectable, BadRequestException } from '@nestjs/common';
import { AntiGigoService } from './anti-gigo.service';
import { TelemetryPayloadDto } from './dto/telemetry-payload.dto';

@Injectable()
export class TelemetryService {
  constructor(private readonly antiGigoService: AntiGigoService) {}

  verifyTelemetry(dto: TelemetryPayloadDto) {
    // 1. Kiểm tra Kinematics
    const kinematicRes = this.antiGigoService.validateKinematics(
      dto.averageSpeedMps,
      dto.horizontalAccuracy,
      dto.isMocked,
    );
    if (!kinematicRes.isValid) {
      throw new BadRequestException(kinematicRes);
    }

    // 2. Kiểm tra Biometrics (IMU / Bước chân)
    const biometricRes = this.antiGigoService.validateBiometrics(
      dto.averageSpeedMps,
      dto.imuSamples,
    );
    if (!biometricRes.isValid) {
      throw new BadRequestException(biometricRes);
    }

    return {
      isValid: true,
      message: 'Step In Valid, Step Out Pure: Dữ liệu cảm biến hợp lệ.',
      dominantFrequencyHz: biometricRes.dominantFrequencyHz,
      estimatedCadenceSpm: biometricRes.estimatedCadenceSpm,
    };
  }
}
