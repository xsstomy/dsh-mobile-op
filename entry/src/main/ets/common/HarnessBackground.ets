/**
 * Deep-ocean atmosphere: vertical gradient + technical dot grid, matching the
 * upstream design language (`Design/design-spec.md`).
 *
 * Usage: `HarnessBackground() { ...page content... }`
 *
 * The gradient is a theme-qualified resource pair, so it follows the app colour
 * mode automatically; the canvas dot grid is repainted every tick from
 * `ThemeRuntime.gridDot`. All three layers carry `expandSafeArea` so the
 * atmosphere also paints underneath the status/navigation bars (immersive
 * window), while page content stays inside the safe area.
 */
import { ThemeRuntime } from './Constants';

interface Particle {
  x: number;
  y: number;
  radius: number;
  speed: number;
  drift: number;
  alpha: number;
}

const PARTICLE_COUNT = 26;

@Component
export struct HarnessBackground {
  @BuilderParam content: () => void = this.emptyContent;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private particles: Particle[] = [];
  private timer: number = -1;
  private frame: number = 0;

  @Builder
  emptyContent() {
  }

  aboutToAppear(): void {
    this.seedParticles();
  }

  aboutToDisappear(): void {
    this.stopAnimation();
  }

  private seedParticles(): void {
    const width = this.context.width;
    const height = this.context.height;
    const particles: Particle[] = [];
    for (let index = 0; index < PARTICLE_COUNT; index += 1) {
      particles.push({
        x: Math.random() * Math.max(width, 1),
        y: Math.random() * Math.max(height, 1),
        radius: 0.8 + Math.random() * 1.8,
        speed: 0.12 + Math.random() * 0.35,
        drift: (Math.random() - 0.5) * 0.25,
        alpha: 0.06 + Math.random() * 0.14
      });
    }
    this.particles = particles;
  }

  /** Slow upward drift; redrawn on a coarse interval to stay power friendly. */
  private startAnimation(): void {
    if (this.timer >= 0) {
      return;
    }
    this.timer = setInterval(() => {
      const width = this.context.width;
      const height = this.context.height;
      this.frame += 1;
      this.context.clearRect(0, 0, width, height);
      this.paintGrid();
      for (const particle of this.particles) {
        particle.y -= particle.speed;
        particle.x += particle.drift;
        if (particle.y < -4) {
          particle.y = height + 4;
          particle.x = Math.random() * Math.max(width, 1);
        }
        if (particle.x < -4) {
          particle.x = width + 4;
        } else if (particle.x > width + 4) {
          particle.x = -4;
        }
        this.context.fillStyle = `rgba(191, 214, 255, ${particle.alpha})`;
        this.context.beginPath();
        this.context.arc(particle.x, particle.y, particle.radius, 0, Math.PI * 2);
        this.context.fill();
      }
    }, 80);
  }

  private stopAnimation(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private paintGrid(): void {
    const width = this.context.width;
    const height = this.context.height;
    const step = 26;
    const size = 2;
    // Canvas paint styles need a literal colour; the theme tick keeps it fresh.
    this.context.fillStyle = ThemeRuntime.gridDot;
    for (let x = 12; x < width; x += step) {
      for (let y = 12; y < height; y += step) {
        this.context.fillRect(x, y, size, size);
      }
    }
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .linearGradient({
          angle: 180,
          colors: [
            [$r('app.color.atmosphere_top'), 0.0],
            [$r('app.color.atmosphere_mid'), 0.44],
            [$r('app.color.atmosphere_bottom'), 1.0]
          ]
        })
      Canvas(this.context)
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onReady(() => {
          this.seedParticles();
          this.paintGrid();
          this.startAnimation();
        })
      this.content()
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
