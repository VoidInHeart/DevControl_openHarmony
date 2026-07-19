@Component
export struct CurtainIcon {
  @Prop iconSize: number = 28;

  build() {
    Image($r('app.media.curtain'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
  }
}
