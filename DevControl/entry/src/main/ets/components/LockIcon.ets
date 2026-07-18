@Component
export struct LockIcon {
  @Prop locked: boolean = true;
  @Prop iconSize: number = 28;

  build() {
    Image(this.locked ? $r('app.media.lock_closed') : $r('app.media.lock_open'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
  }
}
