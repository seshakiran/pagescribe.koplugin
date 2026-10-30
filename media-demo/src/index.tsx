import React from 'react';
import {registerRoot,Composition,Still} from 'remotion';
import {FeatureSlide} from './FeatureSlide';
import {Walkthrough,DURATION} from './Video';
const Root:React.FC=()=> <><Still id="Feature" component={FeatureSlide} width={1920} height={1080} defaultProps={{scene:0}}/><Composition id="Walkthrough" component={Walkthrough} width={1920} height={1080} fps={30} durationInFrames={DURATION}/></>;
registerRoot(Root);
