import React from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { useDeliveryElementContext } from 'components/activities/DeliveryElementProvider';
import { SubmitButton } from 'components/activities/common/delivery/submit_button/SubmitButton';
import { ActivityDeliveryState, isSubmitted, submit } from 'data/activities/DeliveryState';

interface Props {
  disabled?: boolean;
}
export const SubmitButtonConnected: React.FC<Props> = ({ disabled }) => {
  const { context, onSubmitActivity } = useDeliveryElementContext();
  const { graded, surveyId } = context;
  const uiState = useSelector((state: ActivityDeliveryState) => state);
  const dispatch = useDispatch();
  return (
    <SubmitButton
      shouldShow={!isSubmitted(uiState) && !graded && surveyId === null}
      disabled={
        disabled === undefined
          ? Object.values(uiState.partState)
              .map((partState) => partState.studentInput)
              .every((input) => input.length === 0)
          : disabled
      }
      onClick={() => dispatch(submit(onSubmitActivity))}
    />
  );
};
