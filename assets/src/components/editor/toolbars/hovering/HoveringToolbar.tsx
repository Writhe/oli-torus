import React, { useRef, useEffect } from 'react';
import * as ReactDOM from 'react-dom';
import { useSlate } from 'slate-react';
import { CommandContext, CommandDesc } from '../../commands/interfaces';
import { showToolbar, isToolbarHidden, hideToolbar, ToolbarButton } from '../common';
import { marksInEntireSelection } from '../../utils';
import { hoverMenuCommands } from './hoveringToolbarItems';
import { shouldHideToolbar, positionHovering } from './utils';

function hoveringAreEqual(prevProps: HoveringToolbarProps, nextProps: HoveringToolbarProps) {
  return prevProps.commandContext === nextProps.commandContext;
}

export type HoveringToolbarProps = {
  commandContext: CommandContext;
};
export const HoveringToolbar = React.memo((props: HoveringToolbarProps) => {
  const ref = useRef();
  const editor = useSlate();

  useEffect(() => {
    const el = ref.current as any;
    if (!el) {
      return;
    }

    if (shouldHideToolbar(editor)) {
      hideToolbar(el);
    } else {
      isToolbarHidden(el) && positionHovering(el);
      showToolbar(el);
    }
  });

  const style = {
    position: 'absolute',
    zIndex: 1,
    top: '0px',
    left: '0px',
    marginTop: '-18px',
    borderRadius: '4px',
    transition: 'opacity 0.75s',
    backgroundImage: 'linear-gradient(to bottom,rgba(49,49,47,.99),#262625)',
  } as any;

  const isLastInList = (array: any[], index: number) => index === array.length - 1;

  return ReactDOM.createPortal(
    <div ref={(ref as any)} className="hovering-toolbar" style={{ display: 'none', position: 'relative' }}>
      <div style={style} className="btn-group btn-group-sm" role="group" ref={(ref as any)}>
        {hoverMenuCommands.map((cmdDescs: CommandDesc[], cmdDescsIndex) => {
          const buttons = cmdDescs.map((cmdDesc) => {
            const icon = cmdDesc.icon(editor);
            const description = cmdDesc.description(editor);

            const blockLevelItems = ['Title', 'Ordered List', 'Unordered List', 'Quote'];

            const active = cmdDesc.active
              ? blockLevelItems.indexOf(description) > -1
                ? cmdDesc.active(editor)
                : cmdDesc.active(marksInEntireSelection(editor))
              : false;

            return <ToolbarButton
              style="btn-dark"
              active={active}
              key={description}
              description={description}
              icon={icon}
              command={cmdDesc.command}
              context={props.commandContext}
            />;
          });

          const buttonSeparator =
            <div key={'spacer-' + cmdDescsIndex} className="button-separator"></div>;

          return isLastInList(hoverMenuCommands, cmdDescsIndex)
            ? buttons
            : buttons.concat(buttonSeparator);
        })}
      </div>
    </div>, document.body,
  );
}, hoveringAreEqual);
