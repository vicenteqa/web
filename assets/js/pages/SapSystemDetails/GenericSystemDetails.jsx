import React, { useState } from 'react';

import { find, get, noop } from 'lodash';

import {
  EOS_APPLICATION_OUTLINED,
  EOS_DATABASE_OUTLINED,
} from 'eos-icons-react';

import {
  SAP_INSTANCE_START,
  SAP_INSTANCE_STOP,
  getOperationLabel,
  getOperationForbiddenMessage,
} from '@lib/operations';
import { APPLICATION_TYPE, getEnsaVersionLabel } from '@lib/model/sapSystems';

import ListView from '@common/ListView';
import Table from '@common/Table';
import PageHeader from '@common/PageHeader';
import {
  OperationForbiddenModal,
  SimpleAcceptanceOperationModal,
} from '@common/OperationModals';

import DeregistrationModal from '@pages/DeregistrationModal';

import {
  systemHostsTableConfiguration,
  getSystemInstancesTableConfiguration,
} from './tableConfigs';

const renderType = (t) =>
  t === APPLICATION_TYPE ? 'Application server' : 'HANA Database';

const getUniqueHosts = (hosts) =>
  Array.from(
    hosts
      .reduce((hostsMap, host) => {
        if (!hostsMap.has(host.id)) hostsMap.set(host.id, host);
        return hostsMap;
      }, new Map())
      .values()
  );

// it includes SAP and HANA instance operations
const instanceStartStopOperations = [SAP_INSTANCE_START, SAP_INSTANCE_STOP];

const modalInitialState = { open: false, operation: '' };

const closeInstanceModal = (prevState) => ({ ...prevState, open: false });

export function GenericSystemDetails({
  title,
  type,
  system,
  userAbilities,
  cleanUpPermittedFor,
  operationsEnabled = false,
  runningOperations = [],
  getInstanceOperations = noop,
  onInstanceCleanUp = noop,
  onRequestOperation = noop,
  onCleanForbiddenOperation = noop,
}) {
  if (!system) {
    return <div>Not Found</div>;
  }
  const [cleanUpModalOpen, setCleanUpModalOpen] = useState(false);
  const [instanceToDeregister, setInstanceToDeregister] = useState(undefined);
  const [operationModalOpen, setOperationModelOpen] =
    useState(modalInitialState);
  const [currentOperationInstance, setCurrentOperationInstance] =
    useState(undefined);

  const onCleanUpClick = (instance) => {
    setCleanUpModalOpen(true);
    setInstanceToDeregister(instance);
  };

  const curriedGetInstanceOperations = getInstanceOperations(
    runningOperations,
    setOperationModelOpen,
    setCurrentOperationInstance
  );

  const forbiddenOperation = find(runningOperations, { forbidden: true });

  const forbiddenOperationID = get(forbiddenOperation, 'groupID', '');
  const forbiddenOperationName = get(forbiddenOperation, 'operation', null);
  const isForbidden = get(forbiddenOperation, 'forbidden', false);
  const forbiddenErrors = get(forbiddenOperation, 'errors', []);

  return (
    <div>
      <DeregistrationModal
        contentType={type}
        instanceNumber={instanceToDeregister?.instance_number}
        sid={instanceToDeregister?.sid}
        isOpen={!!cleanUpModalOpen}
        onCleanUp={() => {
          setCleanUpModalOpen(false);
          onInstanceCleanUp(instanceToDeregister);
        }}
        onCancel={() => {
          setCleanUpModalOpen(false);
        }}
      />
      <OperationForbiddenModal
        operation={getOperationLabel(forbiddenOperationName)}
        isOpen={isForbidden}
        onCancel={() => onCleanForbiddenOperation(forbiddenOperationID)}
        errors={forbiddenErrors}
      >
        {getOperationForbiddenMessage(forbiddenOperationName)}
      </OperationForbiddenModal>
      <SimpleAcceptanceOperationModal
        operation={operationModalOpen.operation}
        descriptionResolverArgs={{
          instanceNumber: currentOperationInstance?.instance_number,
          sid: currentOperationInstance?.sid,
        }}
        isOpen={
          operationModalOpen.open &&
          instanceStartStopOperations.includes(operationModalOpen.operation)
        }
        onRequest={(params) => {
          onRequestOperation({
            groupID: currentOperationInstance.host_id,
            operation: operationModalOpen.operation,
            requestParams: {
              sapSystemID: system.id,
              hostID: currentOperationInstance.host_id,
              instanceNumber: currentOperationInstance.instance_number,
              params,
            },
          });
          setOperationModelOpen(closeInstanceModal);
        }}
        onCancel={() => {
          setOperationModelOpen(closeInstanceModal);
        }}
      />
      <div className="flex flex-wrap">
        <div className="flex w-1/2 h-auto overflow-hidden overflow-ellipsis break-words">
          <PageHeader className="font-bold">{title}</PageHeader>
        </div>
      </div>
      <div className="mt-4 bg-white shadow rounded-lg py-4 px-8">
        <ListView
          orientation="vertical"
          data={[
            { title: 'Name', content: system.sid },
            {
              title: 'Type',
              content: renderType(type),
            },
            ...(type === APPLICATION_TYPE
              ? [
                  {
                    title: 'ENSA version',
                    content: system.ensa_version || '-',
                    render: (content) => getEnsaVersionLabel(content),
                  },
                ]
              : []),
            {
              title: '',
              content: type,
              render: (content) => (
                <div className="float-right">
                  {content === APPLICATION_TYPE ? (
                    <EOS_APPLICATION_OUTLINED
                      size={25}
                      className="fill-blue-500"
                    />
                  ) : (
                    <EOS_DATABASE_OUTLINED
                      size={25}
                      className="fill-blue-500"
                    />
                  )}
                </div>
              ),
            },
          ]}
        />
      </div>

      <div className="mt-16">
        <div className="flex flex-direction-row">
          <h2 className="text-2xl font-bold self-center">Layout</h2>
        </div>
        <Table
          className="pt-2"
          config={getSystemInstancesTableConfiguration({
            userAbilities,
            cleanUpPermittedFor,
            onCleanUpClick,
            operationsEnabled,
            getOperations: curriedGetInstanceOperations,
          })}
          data={system.instances}
        />
      </div>

      <div className="mt-8">
        <div>
          <h2 className="text-2xl font-bold">Hosts</h2>
        </div>
        <Table
          className="pt-2"
          config={systemHostsTableConfiguration}
          data={getUniqueHosts(system.hosts)}
        />
      </div>
    </div>
  );
}
